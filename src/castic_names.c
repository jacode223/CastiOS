/* Normalize named variables into the 26 AX05 variable slots.
 * Source and function names remain intact. No host compiler is involved.
 */
typedef unsigned int u32;
struct name { char text[32]; char slot; };
static struct name names[26];
static u32 count, used;
static int letter(char c){return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||c=='_';}
static int ident(char c){return letter(c)||(c>='0'&&c<='9');}
static int equal(const char *a,const char *b,u32 length){
 u32 i;for(i=0;i<length;i++)if(!a[i] || a[i]!=b[i])return 0;
 return a[length]==0;
}
static int find(const char *s,u32 length){
 for(u32 i=0;i<count;i++)if(equal(names[i].text,s,length))return (int)i;
 return -1;
}
/* Return normalized byte length, or -1. Destination capacity is 8000. */
int normalize(const char *source,u32 length,char *out){
 if(length>8000)return -1;
 count=0;used=0;
 /* Three passes: reserve old one-letter slots, collect declarations, emit. */
 for(u32 pass=0;pass<3;pass++){
  u32 at=0,written=0;int declaration=0;
  while(at<length){
   char c=source[at];
   if(c=='/'&&at+1<length&&source[at+1]=='/'){
    while(at<length&&source[at]!='\n')at++;
    continue;
   }
   if(c=='\''){
    u32 start=at++;
    while(at<length&&source[at]!='\'')at++;
    if(at==length)return -1;
    at++;
    if(pass==2)while(start<at)out[written++]=source[start++];
    continue;
   }
   if(!letter(c)){
    if(pass==2)out[written++]=c;
    if(c!=' '&&c!='\t'&&c!='\n'&&c!='\r')declaration=0;
    at++;continue;
   }
   u32 start=at;
   while(at<length&&ident(source[at]))at++;
   u32 size=at-start;
   if(size>31)return -1;
   if(size==5&&equal("print",source+start,size)){
    if(pass==2)while(start<at)out[written++]=source[start++];
    while(at<length&&source[at]!=';'&&source[at]!='\n'){
     if(pass==2)out[written++]=source[at];
     at++;
    }
    continue;
   }
   if(pass==0 && size==1 && c>='a'&&c<='z')used|=1U<<(c-'a');
   if(pass==0 && equal("use",source+start,size)){
    /* Preserve register-style library parameters and results. */
    const char *reserved="ap sctkxyv";
    for(u32 i=0;reserved[i];i++)if(reserved[i]!=' ')used|=1U<<(reserved[i]-'a');
   }
   if(pass==1 && declaration && !(size==1 && c>='a' && c<='z') && find(source+start,size)<0){
    const char *keywords[]={"int","let","fn","if","while","return","syscall","print","use"};
    for(u32 i=0;i<9;i++)if(equal(keywords[i],source+start,size))return -1;
    if(count==26)return -1;
    u32 slot=0;while(slot<26&&(used&(1U<<slot)))slot++;
    if(slot==26)return -1;
    used|=1U<<slot;
    for(u32 i=0;i<size;i++)names[count].text[i]=source[start+i];
    names[count].text[size]=0;names[count].slot=(char)('a'+slot);count++;
   }
   declaration=equal("int",source+start,size)||equal("let",source+start,size);
   if(pass==2){
    int index=find(source+start,size);
    u32 next=at;while(next<length&&source[next]==' ')next++;
    if(index>=0 && !(next<length&&source[next]=='('))out[written++]=names[index].slot;
    else while(start<at)out[written++]=source[start++];
   }
  }
  if(pass==2)return (int)written;
 }
 return -1;
}

__asm__(".section .desktop,\"a\"\n.incbin \"examples/castic/desktop.cas\"\n.previous");
