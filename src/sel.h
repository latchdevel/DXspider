/*
 * sel.c
 * 
 * util routines for do the various select activities
 * 
 * Copyright 1996 (c) D-J Koopman
 * 
 * $Header$
 * 
 * $Log$
 * Revision 1.1  2000-03-26 00:03:30  djk
 * first cut of client
 *
 * Revision 1.3  1998/01/02 19:39:57  djk
 * made various changes to cope with glibc
 * fixed problem with extended status in etsi_router
 *
 * Revision 1.2  1997/06/18 18:44:31  djk
 * A working hayes implementation!
 *
 * Revision 1.1  1997/01/28 16:14:23  djk
 * moved these into lib as general routines to use with sel
 *
 * Revision 1.3  1997/01/20 22:30:31  djk
 * Added modem connection for incoming SMS messages
 * Added stats message
 * Added multipack
 *
 * Revision 1.2  1997/01/13 23:34:56  djk
 * The first working test version of smsd
 *
 * Revision 1.1  1997/01/03 23:44:31  djk
 * initial workings
 *
 *
 */

#ifndef _SEL_H
#define _SEL_H

static char _sel_h_rcsid[] = "$Id$";

#include "chain.h"

typedef struct {
	int cnum;						   /* from open */
	short err;						   /* error flag, to delay closing if required */
	short sort;						   /* this thing's sort */
	short flags;						   /* fdset flags */
	char *name;						   /* device name */
	void *fcb;						   /* any fcb associated with this thing */
	reft *msgbase;					   /* any messages for this port */
	int (*handler)();				   /* the handler for this thingy */
} sel_t;

extern sel_t *sel;
extern int sel_max;
extern int sel_top;
extern int sel_inuse;
extern time_t sel_systime;
extern struct timeval sel_tv;

#define SEL_INPUT 1
#define SEL_OUTPUT 2
#define SEL_ERROR 4
#define SEL_IOALL 7

#define SEL_ETSI 1
#define SEL_RMIP 2
#define SEL_SVLP 3
#define SEL_TCP 4
#define SEL_X28 5
#define SEL_STDIO 6
#define SEL_DIALDLE 7
#define SEL_NOKIA 8

void sel_init(int, long, long);					   /* initialise the select thing */
void sel_run();						   /* run the select multiplexor */
sel_t *sel_open(int, void *, char *, int (*)(), int, int);/*  initialise a slot */
void sel_close(sel_t *);
int sel_error(sel_t *, int);		   /* set/clear error flag */

#endif
