/*
 * debug routines
 *
 * Copyright (c) 1998 Dirk Koopman G1TLH
 *
 * $Id$
 */

#ifndef _DEBUG_H
#define _DEBUG_H
extern unsigned long dbglevel;
#define DBGLEVEL(mask) ((dbglevel & mask) == mask)
void dbghup();
void dbginit(char *);
void dbg(unsigned long, char *, ...);
void dbgadd(unsigned long);
void dbgsub(unsigned long);
void dbgset(unsigned long);
void dbgread(char *);
void dbgdump(unsigned long, char *, unsigned char *, int);
void dbgclose();
unsigned long dbgget();
extern void (*dbgproc)();
extern char dbgbuf[];
#endif
