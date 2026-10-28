# libcapt
[![Core tests](https://github.com/darkvision77/libcapt/actions/workflows/core-tests.yml/badge.svg)](https://github.com/darkvision77/libcapt/actions/workflows/core-tests.yml)
[![Compression tests](https://github.com/darkvision77/libcapt/actions/workflows/compression-tests.yml/badge.svg)](https://github.com/darkvision77/libcapt/actions/workflows/compression-tests.yml)

Implementation of the Canon CAPT v1 protocol and SCoA compression based on reverse engineering of the original driver.

**NOTE:** This is not a full-fledged driver that you can install into your system.
    It is an implementation of the compression algorithm and protocol,
    abstracted from any operating system or transmission channel.

## Target devices
Currently, the target devices are Canon CAPT v1 printers, as listed below. \
Support for newer models is not planned in the near future.

| Model   | Cartridge     | PPM (A4) | Max Resolution | Year (approx.) |
|---------|---------------|----------|----------------|----------------|
| LBP800  | EP-22         | 8        | 600 dpi        | 1999-2001      |
| LBP810  | EP-22         | 8        | 600 dpi        | 2001-2002      |
| LBP1120 | EP-22         | 10       | 600 dpi        | 2003-2004      |
| LBP1210 | EP-25         | 14       | 600 dpi        | ~2002          |
| LBP3200 | EP-26/EP-27   | 18       | 600 dpi        | 2004-2006      |

## Status
The protocol is now well enough researched to ensure smooth operation of printing and cleaning.

The most important thing was the absence of any defects/glitches in the printed page.
This was achieved through [comprehensive testing](#validation-of-the-scoa-compression-algorithm)
of the compression algorithm and subsequent verification on real hardware.

The SCoA compression is completely reverse-engineered.
Current implementation of the compression algorithm provides on average 24% better compression
and runs up to 26X faster than the compression implementation of the original driver.

## Usage
If you want to print on a Canon LBP printer, you have several options (besides the original driver):
- [darkvision77/captppd](https://github.com/darkvision77/captppd) — CUPS driver based on libcapt (CAPT v1 only)
- [UoWPrint](https://printserver.ink/) — print server that supports all Canon LBP models (and other printers)
- [mounaiban/captdriver](https://github.com/mounaiban/captdriver) — CUPS driver for the newer Canon LBP models (early alpha stage)

The [`examples`](examples) folder contains an example program for printing PBM files. \
Keep in mind that this program does not implement all the features and is used only for testing.
```sh
cmake -S. -B build -DLIBCAPT_BUILD_EXAMPLES=ON
cmake --build build
./build/examples/printpbm /dev/usb/lp0 ./examples/data/example-1.pbm
```
To rasterize PDF files into PBM, you can use the [`pdf2pbm.sh`](scripts/pdf2pbm.sh) script. Also, you can find some test PBM files in the [`examples/data`](examples/data) folder.

## Compilation
```sh
cmake -S. -B build
cmake --build build
```
### Dependencies
#### Compile-time
- gcc >= 11 or clang >= 16 or MSVC (tested on 19.44.35217.0)
- cmake >= 3.21

#### Testing
- gtest (+ gmock)

##### For compression tests:
- gdb
- python3
- ghostscript
- poppler-utils (`pdfseparate`, `pdfinfo`, etc.)
- captfilter deps (`libpopt0:i386` on Debian)

## Testing
### Core tests
```sh
cmake -S. -B build -DLIBCAPT_BUILD_TESTS=ON
cmake --build build
ctest --test-dir build
```
### Compression tests
```sh
cmake -S. -B build -DLIBCAPT_BUILD_TESTS=ON -DLIBCAPT_COMPRESSION_TESTS=ON
cmake --build build
ctest --test-dir build
```
Compression test files are located at [`tests/Compression/data`](tests/Compression/data).

## Validation of the SCoA compression implementation
As mentioned above, the most important task is to ensure that the printout is correct and free of any glitches.

> ### Brief overview of SCoA compression
> The SCoA stream consists of a sequence of commands.
> For example, the sequence `0x6A 0x12` means “copy two bytes from the previous line and repeat byte `0x12` five times”.
> The command that produced this sequence is called `CopyThenRepeat`.
>
> The commands are implemented in [ScoaCmd.cpp](libcapt/Compression/ScoaCmd.cpp).

For the compression algorithm to work correctly, you need to know how commands are encoded,
what their valid values are, and what commands exist in general.
All of this is pretty easy to find in the `captfilter` binary,
where you can also find their names (thanks to the preserved debug prints).

All that remains is to make tests for all this. This will require a decoder,
that can be used to verify the correctness of the compressor's output data.

But first, you need to make sure that the decoder itself is working properly.
To do this, `captfilter` is launched under the [GDB script](scripts/filter/wrap.py), which records the sequence
of SCoA commands issued by the filter (the so-called command log).
That is, after running `captfilter`, we get compressed data and the sequence
of commands that were called to produce this data.

> ### About the GDB script
> In addition to recording commands, the script also removes all margins,
> as `captfilter` changes the raster size by default, which prevents further
> byte-by-byte comparison of the original raster and the decoded one.
>
> Furthermore, a bug was found in the original driver that causes incorrect printouts
> (noticed when compressing random data). \
> The easiest way to describe it is in code:
> ```c
> char rawData[] = {1, 2, 3, 4, 5, ..., 256};
> CopyThenRawLong(0, rawData, 255); // writes {1, 2, 3, ..., 255}
> // rawData += 255; <- pointer offset was missed
> CopyThenRaw(0, rawData, 1); // writes {1}, but it should be {256}
> ```
> This bug is also fixed by the GDB script.

The decoder, meanwhile, reads the compressed data and also writes a log of the commands it has read.
Next, the resulting command logs are compared to verify that the commands were recognized correctly.
The original raster and the raster obtained by the decoder are also compared to verify the correctness of the commands themselves.

And with a verified decoder, the compression algorithm is tested using
a raster compression and decompression cycle and subsequent comparison.

## SAST Tools
[PVS-Studio](https://pvs-studio.com/pvs-studio/?utm_source=website&utm_medium=github&utm_campaign=open_source) — static analyzer for C, C++, C#, and Java code.

## License
libcapt is licensed under a 2-clause BSD license.
