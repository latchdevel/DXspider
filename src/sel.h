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
 * Revision 1.5  2002-01-27 15:39:59  minima
 * get rid of warning
 *
 * Revision 1.4  2002/01/27 15:35:33  minima
 * try to fix EOF on standard input problems
 *
 * Revision 1.3  2000/07/20 14:16:00  minima
 * can use Sourceforge now!
 * added user->qra cleaning
 * added 4 digit qra to user broadcast dxspots if available
 *
 * Revision 1.2  2000/03/26 14:22:59  djk
 * removed some irrelevant log info
 *
 * Revision 1.1  2000/03/26 00:03:30  djk
 * first cut of client
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
	void (*closehandler)();		/* special close handler */
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

void sel_init(int, long, long);					   /* initialise the select thing */
void sel_run();						   /* run the select multiplexor */
sel_t *sel_open(int, void *, char *, int (*)(), int, int);/*  initialise a slot */
void sel_closehandler(sel_t *, void (*)());	/* post a closehandler for this cnum */

void sel_close(sel_t *);
int sel_error(sel_t *, int);		   /* set/clear error flag */

#endif
