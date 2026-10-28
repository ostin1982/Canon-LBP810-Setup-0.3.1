#include "UsbStream.hpp"
#include "libcapt/BasicCaptPrinter.hpp"
#include "libcapt/Compression/ScoaStreambuf.hpp"
#include "libcapt/Compression/Decoder/DecoderStreambuf.hpp"
#include <iostream>
#include <sstream>
#include <fstream>
#include <random>
#include <atomic>
#include <cctype>
#include <filesystem>

static std::string readA4Pbm(const wchar_t* path) {
    std::ifstream f(std::filesystem::path(path),std::ios::binary);
    if(!f) throw std::runtime_error("Cannot open PBM");
    auto token=[&]() {
        std::string s; char c;
        while(f.get(c)) { if(c=='#') { std::string rest; std::getline(f,rest); continue; } if(!std::isspace(static_cast<unsigned char>(c))) { s+=c; break; } }
        while(f.get(c)) { if(std::isspace(static_cast<unsigned char>(c))) { if(c=='\r' && f.peek()=='\n') f.get(); break; } s+=c; if(s.size()>20) throw std::runtime_error("Invalid PBM token"); }
        return s;
    };
    if(token()!="P4" || token()!="4960" || token()!="7014") throw std::runtime_error("Expected binary P4 PBM, 4960 x 7014 (A4/600 dpi)");
    std::string raw(620*7014,'\0'); f.read(raw.data(),raw.size());
    if(f.gcount()!=static_cast<std::streamsize>(raw.size()) || f.peek()!=std::char_traits<char>::eof()) throw std::runtime_error("PBM data length mismatch");
    return raw;
}

using namespace Capt;
static std::atomic<bool> stopped=false;
static auto deadline=std::chrono::steady_clock::time_point::max();
struct Stop {
    bool stop_requested() const { return stopped || std::chrono::steady_clock::now()>deadline; }
};
static BOOL WINAPI ctrl(DWORD event) {
    if(event==CTRL_C_EVENT || event==CTRL_BREAK_EVENT) { stopped=true; return TRUE; }
    return FALSE;
}
static bool is810(std::string id) {
    // Parse fields so LBP8100 cannot match LBP810.
    std::istringstream fields(id); std::string field; bool canon=false,model=false;
    while(std::getline(fields,field,';')) {
        auto colon=field.find(':'); if(colon==std::string::npos) continue;
        std::string key=field.substr(0,colon),value;
        for(unsigned char c:field.substr(colon+1)) if(std::isalnum(c)) value+=static_cast<char>(std::toupper(c));
        for(char& c:key) c=static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        if(key=="MFG" || key=="MANUFACTURER") canon=value=="CANON";
        if(key=="MDL" || key=="MODEL") model=value=="LBP810" || value=="CANONLBP810";
    }
    return canon && model;
}
static void showStatus(const ExtendedStatus& s) {
    std::cout<<"Basic=0x"<<std::hex<<unsigned(s.Basic)<<" Engine=0x"<<unsigned(s.Engine)
             <<" Controller=0x"<<unsigned(s.Controller)<<std::dec
             <<" Ready="<<s.Ready()<<" Printing="<<s.IsPrinting()<<" Printed="<<s.Printed<<"\n";
}
static std::string testRaster() {
    constexpr int width=4960,height=7014,stride=width/8;
    std::string data(stride*height,'\0');
    auto pixel=[&](int x,int y) { data[y*stride+x/8]|=static_cast<char>(0x80>>(x%8)); };
    for(int y=240;y<height-240;++y) for(int x=240;x<width-240;++x) {
        bool frame=x<246 || x>=width-246 || y<246 || y>=height-246;
        bool grid=y>650 && y<2150 && ((x-240)%240<3 || (y-650)%240<3);
        bool bars=y>2500 && y<3300 && (x/120)%2==0;
        bool ramp=y>3700 && y<4500 && (x+y)%16<(x-240)*16/(width-480);
        if(frame||grid||bars||ramp) pixel(x,y);
    }
    return data;
}
static void selftest() {
    if(!is810("MFG:Canon;MDL:LBP-810;") || is810("MFG:Canon;MDL:LBP8100;") || is810("MFG:Other;MDL:LBP-810;"))
        throw std::runtime_error("Model guard test failed");
    std::mt19937 rng(810);
    for(int kind=0;kind<4;++kind) {
        unsigned stride=kind==3?620:37,lines=kind==3?7014:91;
        std::string raw(stride*lines,'\0');
        if(kind==1) std::fill(raw.begin(),raw.end(),static_cast<char>(255));
        if(kind==2) for(char& c:raw) c=static_cast<char>(rng());
        if(kind==3) raw=testRaster();
        std::istringstream source(raw);
        Compression::ScoaStreambuf enc(*source.rdbuf(),stride,lines);
        std::ostringstream packed; packed<<&enc;
        std::istringstream input(packed.str());
        Compression::DecoderStreambuf dec(*input.rdbuf(),stride,nullptr);
        std::ostringstream restored; restored<<&dec;
        if(restored.str()!=raw) throw std::runtime_error("SCoA roundtrip failed");
        std::cout<<"SCoA roundtrip "<<kind<<": "<<raw.size()<<" -> "<<packed.str().size()<<" bytes OK\n";
    }
    std::ostringstream packet; Protocol::IC_BEGIN_DATA(packet);
    if(packet.str()!=std::string("\xa1\xd0\x04\x00",4)) throw std::runtime_error("Packet framing test failed");
    std::cout<<"Model guard and packet framing OK. Offline tests passed; hardware NOT tested.\n";
}
static void printPage(std::iostream& io,const std::string& raster,unsigned width,unsigned height) {
    BasicCaptPrinter<Stop> printer(io);
    bool reserved=false;
    deadline=std::chrono::steady_clock::now()+std::chrono::minutes(2);
    auto cleanup=[&]() {
        try { printer.GoOffline(); } catch(const std::exception& e) { std::cerr<<"Offline cleanup: "<<e.what()<<"\n"; }
        try { printer.ReleaseUnit(); } catch(const std::exception& e) { std::cerr<<"Release cleanup: "<<e.what()<<"\n"; }
    };
    try {
        printer.ReserveUnit(); reserved=true; printer.ClearError();
        auto ready=printer.WaitStatus(Stop{},[](const ExtendedStatus& s){return s.Ready();},std::chrono::milliseconds(500));
        if(!ready) throw std::runtime_error("Cancelled or printer not ready within 2 minutes");
        showStatus(*ready);
        if(!printer.GoOnline(0)) throw std::runtime_error("Printer refused online state");
        PageParams params{};
        params.PaperSize=0x09; params.TonerDensity=0x3f; params.Resolution=ResolutionIdx::RES_600;
        params.SmoothEnable=true; params.MarginLeft=1; params.MarginTop=1;
        params.ImageLineSize=static_cast<uint16_t>(width/8); params.ImageLines=static_cast<uint16_t>(height);
        params.PaperWidth=4960; params.PaperHeight=7014;
        std::istringstream source(raster);
        Compression::ScoaStreambuf enc(*source.rdbuf(),width/8,height);
        auto info=printer.GetPrinterInfo();
        if(info.BlockSize==0 || info.BlockSize>65531) throw std::runtime_error("Invalid printer block size");
        if(!printer.WriteVideoData(Stop{},params,enc)) throw std::runtime_error("Print transfer interrupted or printer not ready");
        auto end=printer.WaitPrintEnd(Stop{});
        if(!end) throw std::runtime_error("Print completion timeout or cancellation");
        showStatus(*end);
        if(end->VideoDataError() || end->GetReprintStatus()!=ReprintStatus::None || end->Printed<1)
            throw std::runtime_error("Printer has not confirmed successful page completion");
        cleanup(); reserved=false;
        std::cout<<"Printer reports page completed. Please inspect the physical page.\n";
    } catch(...) { if(reserved) cleanup(); throw; }
}
int wmain(int argc,wchar_t** argv) {
    SetConsoleCtrlHandler(ctrl,TRUE);
    std::cout<<"LBP810 USB bridge 0.3 (buffered USB reads)\n";
    try {
        std::wstring cmd=argc>1?argv[1]:L"--list";
        if(cmd==L"--self-test") { selftest(); return 0; }
        if(cmd==L"--make-test-pbm" && argc==3) {
            std::ofstream f(argv[2],std::ios::binary); auto raw=testRaster();
            f<<"P4\n4960 7014\n"; f.write(raw.data(),raw.size());
            if(!f) throw std::runtime_error("Cannot write PBM"); return 0;
        }
        if(cmd==L"--validate-pbm" && argc==3) { readA4Pbm(argv[2]); std::cout<<"Valid A4 PBM\n"; return 0; }
        if(cmd!=L"--list" && cmd!=L"--status" && cmd!=L"--print-test" && !(cmd==L"--print-pbm" && argc==3)) {
            std::cout<<"Usage: Lbp810Usb.exe --list | --status | --print-test | --print-pbm path | --validate-pbm path | --self-test | --make-test-pbm path\n"; return 2;
        }
        std::string raster;
        if(cmd==L"--print-pbm") raster=readA4Pbm(argv[2]);
        auto paths=usbPrinters(); std::vector<std::wstring> matches;
        std::cout<<"Present USB printer interfaces: "<<paths.size()<<"\n";
        for(const auto& path:paths) {
            std::wcout<<L"Path: "<<path<<L"\n";
            try { UsbStream usb(path); auto id=usb.identity(); std::cout<<"IEEE1284: "<<id<<"\n"; if(is810(id)) matches.push_back(path); }
            catch(const std::exception& e) { std::cerr<<"Cannot inspect interface: "<<e.what()<<"\n"; }
        }
        if(cmd==L"--list") { std::cout<<"Confirmed Canon LBP-810 devices: "<<matches.size()<<"\n"; return matches.empty()?3:0; }
        if(matches.size()!=1) throw std::runtime_error("Exactly one confirmed Canon LBP-810 is required. Connect and power it on, then run --list.");
        UsbStream usb(matches[0]); std::iostream io(&usb); io.exceptions(std::ios::badbit|std::ios::failbit);
        if(cmd==L"--status") {
            auto info=Protocol::PC_GET_PRINTER_INFO(io);
            std::cout<<"CAPT device="<<unsigned(info.DeviceId)<<" type="<<unsigned(info.Type)<<" block="<<info.BlockSize<<"\n";
            showStatus(Protocol::PC_GET_EXTENDED_STATUS(io)); return 0;
        }
        std::cout<<"Printing one A4 600-dpi page directly over USB. Ctrl+C cancels.\n";
        printPage(io,cmd==L"--print-pbm"?raster:testRaster(),4960,7014); return 0;
    } catch(const std::exception& e) { std::cerr<<"ERROR: "<<e.what()<<"\n"; return 1; }
}
