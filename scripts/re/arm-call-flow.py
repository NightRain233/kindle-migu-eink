# 用法: arm-call-flow.py <lib.so> <objdump.s> <lo_hex> <hi_hex>  列出区间内的导入调用与 lab126_log_write 格式串（names 表需按目标库调整）
import re, struct, sys
from elftools.elf.elffile import ELFFile
lib=sys.argv[1]; asm=sys.argv[2]; lo=int(sys.argv[3],16); hi=int(sys.argv[4],16)
elf=ELFFile(open(lib,'rb'))
def rd(va,n):
    for seg in elf.iter_segments():
        if seg['p_type']=='PT_LOAD' and seg['p_vaddr']<=va<seg['p_vaddr']+seg['p_filesz']:
            return seg.data()[va-seg['p_vaddr']:va-seg['p_vaddr']+n]
def cstr(va):
    b=rd(va,200) or b''
    return b.split(b'\0')[0].decode('latin1')
names={'0x24a4':'VectorImpl()','0x24b0':'String8()','0x24bc':'Vector.add','0x24c8':'readExceptionCode','0x24d4':'LOG','0x24e0':'readInt32','0x24ec':'readString16','0x24f8':'~String16','0x2504':'String8(String16)','0x2510':'String8.setTo','0x251c':'~String8'}
regs={}
for line in open(asm):
    m=re.match(r'\s+([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*\t(\S+)\s*(.*)',line)
    if not m: continue
    a=int(m.group(1),16); op=m.group(3); args=re.sub(r'<[^>]*>','',m.group(4)).split('@')[0].strip()
    mm=re.match(r'(r\d+|r11|r10|r9|r8),\s*\[pc,\s*#(-?\d+)\]',args)
    if op.startswith('ldr') and mm:
        lit=((a+4)&~3)+int(mm.group(2)); regs[mm.group(1)]=struct.unpack('<I',rd(lit,4))[0]
    mm=re.match(r'(r\d+),\s*pc$',args)
    if op=='add' and mm and mm.group(1) in regs:
        regs[mm.group(1)]=(regs[mm.group(1)]+a+4)&0xffffffff
    if a<lo or a>=hi: continue
    t=re.search(r'(0x[0-9a-f]+)',args)
    if op.startswith('blx') and t and t.group(1) in names:
        n=names[t.group(1)]
        if n=='LOG': print(f'{a:5x}: LOG "{cstr(regs.get("r3",0))}"')
        else: print(f'{a:5x}: {n}')
    elif op.startswith('bl') and t: print(f'{a:5x}: call {t.group(1)}')
    elif op in('b','beq','bne','bge','bgt','blt','ble','cbz','cbnz','b.w','bge.w','blt.w','beq.w','bne.w') or op.startswith('cmp'): print(f'{a:5x}:   {op} {args}')
