
/*
 * chain base definitions
 */


#ifndef _CHAIN_DEFS			/* chain definitions */

typedef struct _reft
{
	struct _reft *next, *prev;
} reft;

extern void chain_init(reft *);
extern void chain_insert(reft *, void *);
extern void chain_add(reft *, void *);
extern void *chain_delete(void *);
extern void *chain_get_next(reft *, void *);
extern void *chain_get_prev(reft *, void *);
extern void chain_rechain(reft *, void *);
extern int  chain_empty_test(reft *);
extern void chain_flush(reft *);
extern reft *chain_new(void);

#define is_chain_empty chain_empty_test

#define _CHAIN_DEFS
#endif
