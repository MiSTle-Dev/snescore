#!/usr/bin/python3
# convert a snes sfc into a hex file expected by the verilator sim

import sys

def sfc_read(name):
    try:    
        with open(name, 'rb') as f:
            data = f.read()
            f.close()
            return data
    except Exception as e:
        print("Error reading", name, ":", e)
        return None

def hex_write(name, data):
    try:    
        with open(name, 'w') as f:
            for b in data:
                f.write(bytes([b]).hex()+'\n')
            f.close()
    except Exception as e:
        print("Error writing", name, ":", e)

def sfc_check_header(data):
    if len(data) != 32: return None

    # Game Title registration $ffc0, 21 bytes
    name = data[:21]
    if not name.isascii():
        return None

    print("NAME:", name. decode('ASCII'))

    # Map Mode $ffd5, 1 byte
    rommode = { 0: "LoROM", 1: "HiROM", 2: "S-DD1", 3: "SA-1", 5: "ExHirROM", 10: "SPC7110" }

    if data[21] & 0b11100000 != 0b00100000 or not (data[21]&15) in rommode:
        print("invalid rom mode", hex(data[21]))
        return None

    print("ROM:", "fast" if (data[21] & 0x10) else "slow", rommode[data[21]&15])

    # Cartridge Type $ffd6, 1 byte
    chipset = {    
        0x0: "ROM only",
        0x1: "ROM + RAM",
        0x2: "ROM + RAM + battery",
        0x3: "ROM + coprocessor",
        0x4: "ROM + coprocessor + RAM",
        0x5: "ROM + coprocessor + RAM + battery",
        0x6: "ROM + coprocessor + battery"
    }

    coprocessor = {
        0x0: "DSP (DSP-1, 2, 3 or 4)",
        0x1: "GSU (SuperFX)",
        0x2: "OBC1",
        0x3: "SA-1",
        0x4: "S-DD1",
        0x5: "S-RTC",
        0xE: "Other (Super Game Boy/Satellaview)",
        0xF: "Custom (specified with $FFBF)"
    }

    if not data[22]&15 in chipset: return None
    print("Chipset:", chipset[data[22]&15])

    if (data[22]&15) >= 3 and (data[22]&15) <= 6:
        if not data[22]>>4 in coprocessor: return None
        print("Coprocessor:", coprocessor[data[22]>>4])

    # ROM Size $ffd7, 1 byte
    print("ROM Size:", 1<<data[23], "kb")
    
    # RAM Size $ffd8, 1 byte
    if data[24] > 7: return None
    if data[22]&15 == 1 or data[22]&15 == 2 or data[22]&15 == 4 or data[22]&15 == 5:
        print("RAM Size:", 1<<data[24])

    country = {
        0x00: "Japan",
        0x01: "North America",
        0x02: "Europe",
        0x03: "Scandinavia",
        0x04: "Finland",
        0x05: "Denmark",
        0x06: "Europe (French only)",
        0x07: "Dutch",
        0x08: "Spanish",
        0x09: "German",
        0x0A: "Italian",
        0x0B: "Chinese",
        0x0C: "Indonesia",
        0x0D: "South Korea",
        0x0E: "Common", 	
        0x0F: "Canada",
        0x10: "Brazil", 	
        0x10: "Nintendo Gateway System",
        0x11: "Australia",
        0x12: "Other variation",
        0x13: "Other variation",
        0x14: "Other variation"
    }

    # Destinantion Code $ffd9, 1 byte
    if not data[25] in country: return None    
    print("Country:", country[data[25]])

    # Developer ID $ffda, 1 byte
    print("Developer ID:", data[26])

    # header seems ok, return it
    return data
    
def sfc_analyze(data):
    l = len(data)

    # rom size should at least be 128k
    if l < 128*1024: return None

    # check for sane rom size
    if l & (128*1024-1) & ~(1<<9): return None
    
    # check if 512 byte header is present
    if not l & (1<<9):
        print("No 512 byte header present")

        # try to find the header inside the data at either 0x7fc0 or 0xffc0
        header = sfc_check_header(data[0x7fc0:0x7fc0+32])
        if not header:
            header = sfc_check_header(data[0xffc0:0xffc0+32])        

        if not header:
            print("No valid header found")
            return none

        # prepend header
        return header + bytes(512-32) + data        
        
    else:
        print("512 byte header already present")
        sfc_check_header(data[0:32])

        return data

if __name__ == "__main__":
    print("=== sfc2hex ===")

    if len(sys.argv) != 3:
        print("Usage: sfc2hex <sfcfile> <hexfile>")
        sys.exit(-1)

    data = sfc_read(sys.argv[1])
    if not data: sys.exit(-1)

    data = sfc_analyze(data)
        
    if data: hex_write(sys.argv[2], data)

        
