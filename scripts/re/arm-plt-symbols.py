# 用法: arm-plt-symbols.py <lib.so> <plt_stub_addr_hex>...  打印每个 PLT stub 对应的导入符号
import sys, struct, subprocess
from elftools.elf.elffile import ELFFile
path = sys.argv[1]; want = [int(a,16) for a in sys.argv[2:]]
f = open(path,'rb'); elf = ELFFile(f)
got2sym = {}
for name in ('.rel.plt','.rel.dyn'):
    sec = elf.get_section_by_name(name)
    if not sec: continue
    symtab = elf.get_section(sec['sh_link'])
    for r in sec.iter_relocations():
        if r['r_info_sym']:
            got2sym[r['r_offset']] = symtab.get_symbol(r['r_info_sym']).name
plt = elf.get_section_by_name('.plt')
data = plt.data(); base = plt['sh_addr']
def stub_target(addr):
    off = addr - base
    i0,i1,i2 = struct.unpack_from('<III', data, off)
    def rot(imm12):
        rot = (imm12>>8)&0xf; v = imm12&0xff
        return ((v >> (2*rot)) | (v << (32-2*rot))) & 0xffffffff
    return addr + 8 + rot(i0&0xfff) + rot(i1&0xfff) + (i2&0xfff)
def dm(s):
    try: return subprocess.run(['c++filt'],input=s,capture_output=True,text=True).stdout.strip()
    except Exception: return s
for a in want:
    g = stub_target(a)
    print(hex(a), hex(g), dm(got2sym.get(g,'?')))
