#pragma once
#define NOMINMAX
#include <windows.h>
#include <setupapi.h>
#include <string>
#include <vector>
#include <streambuf>
#include <stdexcept>
#include <system_error>
#include <algorithm>

inline void usbError(DWORD code,const char* what) {
    throw std::runtime_error(std::string(what)+": Win32 error "+std::to_string(code));
}
inline void winfail(const char* what) { usbError(GetLastError(),what); }
inline const GUID UsbPrinterGuid = {0x28d78fad,0x5a12,0x11d1,{0xae,0x5b,0,0,0xf8,3,0xa8,0xc2}};
inline std::vector<std::wstring> usbPrinters() {
    HDEVINFO set = SetupDiGetClassDevsW(&UsbPrinterGuid,nullptr,nullptr,DIGCF_PRESENT|DIGCF_DEVICEINTERFACE);
    if(set==INVALID_HANDLE_VALUE) winfail("SetupDiGetClassDevs");
    std::vector<std::wstring> paths;
    try {
        for(DWORD i=0;;++i) {
            SP_DEVICE_INTERFACE_DATA item{}; item.cbSize=sizeof(item);
            if(!SetupDiEnumDeviceInterfaces(set,nullptr,&UsbPrinterGuid,i,&item)) {
                if(GetLastError()==ERROR_NO_MORE_ITEMS) break;
                winfail("SetupDiEnumDeviceInterfaces");
            }
            DWORD size=0;
            SetupDiGetDeviceInterfaceDetailW(set,&item,nullptr,0,&size,nullptr);
            if(!size) winfail("USB interface size");
            std::vector<unsigned char> mem(size);
            auto detail=reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(mem.data());
            detail->cbSize=sizeof(*detail);
            if(!SetupDiGetDeviceInterfaceDetailW(set,&item,detail,size,nullptr,nullptr)) winfail("USB interface path");
            paths.emplace_back(detail->DevicePath);
        }
    } catch(...) { SetupDiDestroyDeviceInfoList(set); throw; }
    SetupDiDestroyDeviceInfoList(set); return paths;
}

class UsbStream : public std::streambuf {
    HANDLE h=INVALID_HANDLE_VALUE;
    // Read an entire USB response into a packet-sized buffer. The CAPT parser
    // consumes 1/2-byte fields; forwarding those tiny reads to USB may overrun
    // the host transfer when the device returns a complete response packet.
    char input[65536]{};
    DWORD transfer(bool reading, void* buffer, DWORD size) {
        OVERLAPPED ov{}; ov.hEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);
        if(!ov.hEvent) winfail("CreateEvent");
        DWORD count=0;
        BOOL ok=reading ? ReadFile(h,buffer,size,&count,&ov) : WriteFile(h,buffer,size,&count,&ov);
        DWORD error=ok ? ERROR_SUCCESS : GetLastError();
        if(!ok && error==ERROR_IO_PENDING) {
            DWORD wait=WaitForSingleObject(ov.hEvent,5000);
            if(wait!=WAIT_OBJECT_0) {
                CancelIoEx(h,&ov);
                GetOverlappedResult(h,&ov,&count,TRUE);
                CloseHandle(ov.hEvent);
                throw std::runtime_error("USB I/O timeout (5 seconds); no response from printer");
            }
            ok=GetOverlappedResult(h,&ov,&count,FALSE); error=ok?ERROR_SUCCESS:GetLastError();
        }
        CloseHandle(ov.hEvent);
        if(!ok) usbError(error,reading?"USB read":"USB write");
        if(!count && size) throw std::runtime_error("USB returned an empty transfer");
        return count;
    }
protected:
    std::streamsize xsputn(const char* p,std::streamsize n) override {
        std::streamsize done=0;
        while(done<n) done+=transfer(false,const_cast<char*>(p+done),static_cast<DWORD>(std::min<std::streamsize>(n-done,16384)));
        return done;
    }
    int_type overflow(int_type c) override {
        if(traits_type::eq_int_type(c,traits_type::eof())) return traits_type::not_eof(c);
        char b=traits_type::to_char_type(c); xsputn(&b,1); return c;
    }
    std::streamsize xsgetn(char* p,std::streamsize n) override {
        std::streamsize done=0;
        while(done<n) {
            if(traits_type::eq_int_type(underflow(),traits_type::eof())) break;
            auto count=std::min<std::streamsize>(n-done,egptr()-gptr());
            std::copy_n(gptr(),count,p+done); gbump(static_cast<int>(count)); done+=count;
        }
        return done;
    }
    int_type underflow() override {
        if(gptr() && gptr()<egptr()) return traits_type::to_int_type(*gptr());
        DWORD count=transfer(true,input,sizeof(input));
        setg(input,input,input+count); return traits_type::to_int_type(*gptr());
    }
public:
    explicit UsbStream(const std::wstring& path) {
        h=CreateFileW(path.c_str(),GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,FILE_FLAG_OVERLAPPED,nullptr);
        if(h==INVALID_HANDLE_VALUE) winfail("Open USB printer");
    }
    ~UsbStream() override { if(h!=INVALID_HANDLE_VALUE) CloseHandle(h); }
    UsbStream(const UsbStream&)=delete;
    UsbStream& operator=(const UsbStream&)=delete;
    std::string identity() {
        // CTL_CODE(FILE_DEVICE_UNKNOWN, 13, METHOD_BUFFERED, FILE_ANY_ACCESS)
        constexpr DWORD getId=(0x22u<<16)|(13u<<2);
        char data[4094]{}; DWORD count=0;
        OVERLAPPED ov{}; ov.hEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);
        if(!ov.hEvent) winfail("CreateEvent");
        BOOL ok=DeviceIoControl(h,getId,nullptr,0,data,sizeof(data),&count,&ov);
        DWORD error=ok?0:GetLastError();
        if(!ok && error==ERROR_IO_PENDING) {
            DWORD wait=WaitForSingleObject(ov.hEvent,5000);
            if(wait!=WAIT_OBJECT_0) {
                CancelIoEx(h,&ov); GetOverlappedResult(h,&ov,&count,TRUE); CloseHandle(ov.hEvent);
                throw std::runtime_error("USB identity timeout");
            }
            ok=GetOverlappedResult(h,&ov,&count,FALSE); error=ok?0:GetLastError();
        }
        CloseHandle(ov.hEvent);
        if(!ok) usbError(error,"GET_1284_ID");
        if(count<2) throw std::runtime_error("Missing IEEE 1284 device ID");
        std::string id(data+2,data+count);
        while(!id.empty() && id.back()=='\0') id.pop_back();
        return id;
    }
};
