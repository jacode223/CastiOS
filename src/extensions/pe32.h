/* Clean-room PE32 reader. All offsets and RVAs are checked before access.
 * This inspects images; it never maps or executes untrusted PE code. */
#ifndef CASTIOS_PE32_H
#define CASTIOS_PE32_H
typedef unsigned char pe_u8;
typedef unsigned short pe_u16;
typedef unsigned int pe_u32;
struct pe_image {
 pe_u32 image_base, entry, image_size, section_count, import_count;
 pe_u16 machine, subsystem;
 pe_u32 resource_rva, resource_size, resource_types;
};
typedef void (*pe_import_cb)(void *, const char *, const char *);
static pe_u16 pe16(const pe_u8 *p){return (pe_u16)(p[0]|p[1]<<8);}
static pe_u32 pe32(const pe_u8 *p){return (pe_u32)p[0]|(pe_u32)p[1]<<8|(pe_u32)p[2]<<16|(pe_u32)p[3]<<24;}
static int pe_range(pe_u32 at,pe_u32 n,pe_u32 size){return at<=size&&n<=size-at;}
static const char *pe_error(int code){
 switch(code){case -1:return "cabecera DOS/PE invalida";
 case -2:return "solo PE32 x86 (i386)";
 case -3:return "secciones PE fuera del archivo o solapadas";
 case -4:return "directorio de importaciones invalido";
 case -5:return "limite de importaciones excedido";
 case -6:return "directorio de recursos invalido";
 default:return "PE invalido";}
}
static int pe_string(const pe_u8 *b,pe_u32 size,pe_u32 at,pe_u32 cap){
 if(at>=size)return 0;
 for(pe_u32 n=0;n<cap&&n<size-at;n++)if(!b[at+n])return n>0;
 return 0;
}
/* Return raw file offset for an RVA. Headers and zero-fill tails do not
 * count as import data, preventing reads through nonexistent file bytes. */
static int pe_raw(const pe_u8 *b,pe_u32 size,pe_u32 table,pe_u32 count,
                  pe_u32 rva,pe_u32 bytes,pe_u32 *out){
 for(pe_u32 i=0;i<count;i++){
  const pe_u8 *s=b+table+i*40;
  pe_u32 va=pe32(s+12),raw=pe32(s+20),len=pe32(s+16);
  if(rva>=va&&rva-va<len&&bytes<=len-(rva-va)){
   pe_u32 off=raw+(rva-va);
   if(off>=raw&&pe_range(off,bytes,size)){*out=off;return 1;}
  }
 }
 return 0;
}
static int pe_parse(const pe_u8 *b,pe_u32 size,struct pe_image *info,
                    pe_import_cb emit,void *ctx){
 if(!b||!info||!pe_range(0,64,size)||pe16(b)!=0x5a4d)return -1;
 pe_u32 nt=pe32(b+0x3c);
 if(!pe_range(nt,24,size)||pe32(b+nt)!=0x00004550)return -1;
 pe_u16 machine=pe16(b+nt+4),count=pe16(b+nt+6),opt=pe16(b+nt+20);
 if(machine!=0x14c||!pe_range(nt+24,opt,size)||opt<96||
    pe16(b+nt+24)!=0x10b)return -2;
 if(!count||count>96)return -3;
 pe_u32 table=nt+24+opt;
 if(!pe_range(table,(pe_u32)count*40,size))return -3;
 const pe_u8 *o=b+nt+24;
 pe_u32 entry=pe32(o+16),base=pe32(o+28),image=pe32(o+56);
 if(!image||!base||entry>=image)return -3;
 for(pe_u32 i=0;i<count;i++){
  const pe_u8*s=b+table+i*40;
  pe_u32 va=pe32(s+12),raw=pe32(s+20),len=pe32(s+16);
  pe_u32 virtual_len=pe32(s+8);
  if(va>image||virtual_len>image-va||
     (len&&(!pe_range(raw,len,size)||len>image-va)))return -3;
  if(len)for(pe_u32 j=0;j<i;j++){
   const pe_u8*t=b+table+j*40;
   pe_u32 r=pe32(t+20),n=pe32(t+16);
   if(n&&raw<r+n&&r<raw+len)return -3;
  }
 }
 *info=(struct pe_image){base,entry,image,count,0,machine,pe16(o+68),0,0,0};
 /* Resource directory (entry 2): report top-level types, never execute data.
  * A bounded directory is required; nested contents remain uninspected. */
 if(pe32(o+92)>=3){
  if(opt<120)return -6;
  pe_u32 rr=pe32(o+112),rs=pe32(o+116),off;
  if(rr||rs){
   if(!rr||rs<16||rs>1048576||!pe_raw(b,size,table,count,rr,rs,&off))return -6;
   pe_u32 n=(pe_u32)pe16(b+off+12)+pe16(b+off+14);
   if(n>1024||n>(rs-16)/8)return -6;
   info->resource_rva=rr;info->resource_size=rs;info->resource_types=n;
  }
 }
 if(opt<104||pe32(o+92)<2)return 0;
 if(opt<112)return -4;
 pe_u32 imports=pe32(o+104),imports_len=pe32(o+108);
 if(!imports&&!imports_len)return 0;
 if(!imports||imports_len<20||imports_len>4096)return -4;
 pe_u32 dir;
 if(!pe_raw(b,size,table,count,imports,imports_len,&dir))return -4;
 int terminated=0;
 for(pe_u32 d=0;d+20<=imports_len;d+=20){
  const pe_u8 *desc=b+dir+d;
  pe_u32 lookup=pe32(desc),name=pe32(desc+12),iat=pe32(desc+16);
  if(!lookup&&!name&&!iat){terminated=1;break;}
  if(++info->import_count>64||!name||!iat)return -5;
  pe_u32 dll;
  if(!pe_raw(b,size,table,count,name,1,&dll)||!pe_string(b,size,dll,96))return -4;
  if(!lookup)lookup=iat;
  int end=0;
  for(pe_u32 n=0;n<1024;n++){
   pe_u32 at,v;
   if(lookup>0xffffffffU-n*4||
      !pe_raw(b,size,table,count,lookup+n*4,4,&at))return -4;
   v=pe32(b+at);if(!v){end=1;break;}
   if(v&0x80000000U){if(emit)emit(ctx,(const char*)b+dll,"#ordinal");continue;}
   pe_u32 str;
   if(!pe_raw(b,size,table,count,v,3,&str)||
      !pe_string(b,size,str+2,128))return -4;
   if(emit)emit(ctx,(const char*)b+dll,(const char*)b+str+2);
  }
  if(!end)return -5;
 }
 return terminated?0:-4;
}
#endif
