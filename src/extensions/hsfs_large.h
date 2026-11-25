/* HSFS5: large files use contiguous sectors outside mirrored metadata. */
#define HSFS_BIG_MAX 104857600U
#define HSFS_DATA_START 16384U
#define HSFS_SWAP_RESERVE 8192U /* 4 MiB at the physical end of the disk */
#define CP_CHUNK 1474560U /* 1.44 MiB, exactly 2880 sectors */

struct cp_job {
 struct fatvol *vol;
 struct fatent ent;
 char dest[128];
 u32 parent,slot,start,count,left,cl,sector,hops,pos;
 char name[32];
};

static int hsfs_source(const char *source,struct fatvol **vol,struct fatent *ent){
 char src[256];const char *relative;
 if(!normalize(source,src)||!xprefix(src,"/mnt/"))return 0;
 *vol=volume(src,&relative);
 return *vol&&lookup(*vol,relative,ent)&&!(ent->attr&16);
}

static int hsfs_copy_chunk(struct cp_job *j){
 u32 bytes=j->left<CP_CHUNK?j->left:CP_CHUNK;
 u32 sectors=(bytes+511)/512;
 for(u32 i=0;i<sectors;i++){
  if(j->cl<2||j->cl>j->vol->clusters+1||++j->hops>j->vol->clusters*j->vol->spc)
   return xerr("cp: cadena FAT32 invalida");
  if(!vread(j->vol,j->vol->data+(j->cl-2)*j->vol->spc+j->sector,BLOB+i*512))
   return xerr("cp: lectura FAT32 fallida");
  j->sector++;
  if(j->sector==j->vol->spc && i+1<sectors){
   j->cl=nextcl(j->vol,j->cl);j->sector=0;
   if(j->cl<2||j->cl==0xffffffff)return xerr("cp: cadena FAT32 truncada");
  }
 }
 if(bytes&511)zero(BLOB+bytes,512-(bytes&511));
 for(u32 i=0;i<sectors;i++)
  if(X.write_sector(*X.selected_disk,*X.volume_base+j->start+j->pos+i,BLOB+i*512))
   return xerr("cp: escritura de disco fallida");
 j->pos+=sectors;j->left-=bytes;
 if(j->left && j->sector==j->vol->spc){
  j->cl=nextcl(j->vol,j->cl);j->sector=0;
  if(j->cl<2||j->cl==0xffffffff)return xerr("cp: cadena FAT32 truncada");
 }
 return 0;
}

/* Round-robin jobs. The PIO controller still performs each I/O serially. */
static int hsfs_bigcopy_many(const char *const *sources,const char *const *dests,u32 n){
 if(!*X.persistent_fs)return xerr("HSFS: requiere disco persistente");
 if(n<1||n>2)return xerr("cp: maximo dos transferencias");
 struct cp_job jobs[2];zero(jobs,sizeof jobs);
 memcopy((void*)FS,(void*)0x200000,512+COUNT*REC);cwd=*X.cwd;
 for(u32 k=0;k<n;k++){
  struct cp_job*j=&jobs[k];
  if(!hsfs_source(sources[k],&j->vol,&j->ent))return xerr("cp: origen FAT32 no encontrado");
  if(!j->ent.size||j->ent.size>HSFS_BIG_MAX)return xerr("cp: archivo grande entre 1 byte y 100 MiB");
  if(j->vol->disk==*X.selected_disk)return xerr("cp: origen y destino en el mismo disco");
  if(!xcopy(j->dest,dests[k],sizeof j->dest))return xerr("cp: destino demasiado largo");
  if(resolve(j->dest,&j->parent,j->name)!=-1||!j->name[0])return xerr("cp: destino existente o invalido");
  for(u32 p=0;p<k;p++)
   if(jobs[p].parent==j->parent&&eq(jobs[p].name,j->name))return xerr("cp: destinos duplicados");
  j->slot=COUNT;
  for(u32 i=0;i<COUNT;i++)if(!*record(i)){
   int taken=0;for(u32 p=0;p<k;p++)if(jobs[p].slot==i)taken=1;
   if(!taken){j->slot=i;break;}
  }
  if(j->slot==COUNT)return xerr("HSFS: sin metadatos libres");
  j->count=(j->ent.size+511)/512;
  u32 base=*X.volume_base,cap=X.caps[*X.selected_disk];
  if(base>=cap||cap-base<=HSFS_DATA_START+HSFS_SWAP_RESERVE||j->count>cap-base-HSFS_DATA_START-HSFS_SWAP_RESERVE)return xerr("HSFS: disco demasiado pequeno");
  /* First fit: a deleted large file leaves reusable sectors. Include
   * earlier jobs in this transaction so concurrent copies never overlap. */
  u32 start=HSFS_DATA_START,limit=cap-base-HSFS_SWAP_RESERVE;
  for(;;){
   if(start>limit||j->count>limit-start)return xerr("HSFS: disco demasiado pequeno");
   u32 next=start;
   for(u32 i=0;i<COUNT;i++){
    u8*r=record(i);if(!*r||rd(r+36)!=5)continue;
    u32 lo=rd(r+48),hi=lo+rd(r+52);
    if(lo<start+j->count&&start<hi&&hi>next)next=hi;
   }
   for(u32 p=0;p<k;p++){
    u32 lo=jobs[p].start,hi=lo+jobs[p].count;
    if(lo<start+j->count&&start<hi&&hi>next)next=hi;
   }
   if(next==start)break;
   start=next;
  }
  j->start=start;
  j->left=j->ent.size;j->cl=j->ent.cluster;
 }
 for(;;){
  u32 active=0;
  for(u32 k=0;k<n;k++)if(jobs[k].left){active++;if(hsfs_copy_chunk(&jobs[k]))return 1;}
  if(!active)break;
 }
 if(X.flush_disk())return xerr("cp: datos sin confirmar");
 for(u32 k=0;k<n;k++){
  struct cp_job*j=&jobs[k];u8*r=record(j->slot);
  if(j->pos!=j->count)return xerr("cp: transferencia incompleta");
  zero(r,REC);memcopy(r,j->name,strlen_(j->name));wr(r+32,j->parent);wr(r+36,5);
  wr(r+40,j->ent.size);wr(r+48,j->start);wr(r+52,j->count);
 }
 dirty=1;changed();
 if(validate_fs(FS))return xerr("cp: metadatos invalidos; transaccion descartada");
 for(u32 k=0;k<n;k++){xs("Copiado a HSFS: ");xs(jobs[k].dest);xs(" ");xn(jobs[k].ent.size);xs(" bytes.\n");}
 return 2;
}

static int hsfs_bigcopy(const char *source,const char *dest){
 const char *sources[1]={source},*dests[1]={dest};
 return hsfs_bigcopy_many(sources,dests,1);
}
