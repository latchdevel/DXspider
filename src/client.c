/*
 * C Client for the DX Spider cluster program
 *
 * Eventually this program will be a complete replacement
 * for the perl version.
 *
 * This program provides the glue necessary to talk between
 * an input (eg from telnet or ax25) and the perl DXSpider
 * node.
 *
 * Currently, this program connects STDIN/STDOUT to the
 * message system used by cluster.pl
 *
 * Copyright (c) 2000 Dirk Koopman G1TLH
 *
 * $Id$
 */

#include <stdio.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
#include <ctype.h>
#include <stdlib.h>
#include <stdarg.h>
#include <netdb.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <errno.h>
#include <signal.h>
#include <string.h>
#include <termios.h>

#include "sel.h"
#include "cmsg.h"
#include "debug.h"

#define TEXT 1
#define MSG 2
#define MAXBUFL 1024

#define DBUF 1
#define DMSG 2

typedef struct 
{
	int cnum;					/* the connection number */
	int sort;					/* the type of connection either text or msg */
	cmsg_t *in;					/* current input message being built up */
	cmsg_t *out;				/* current output message being sent */
	reft *inq;					/* input queue */
	reft *outq;					/* output queue */
	sel_t *sp;					/* my select fcb address */
	int echo;					/* echo characters back to this cnum */
	struct termios t;			/* any termios associated with this cnum */
} fcb_t;

char *node_addr = "localhost";	/* the node tcp address */
int node_port = 27754;			/* the tcp port of the node at the above address */
char *call;						/* the caller's callsign */
char *connsort;					/* the type of connection */
fcb_t *in;						/* the fcb of 'stdin' that I shall use */
fcb_t *node;					/* the fcb of the msg system */
char nl = '\n';					/* line end character */
char ending = 0;				/* set this to end the program */
char send_Z = 1;				/* set a Z record to the node on termination */
char echo = 1;					/* echo characters on stdout from stdin */

void terminate(int);

/*
 * utility routines - various
 */

void die(char *s, ...)
{
	char buf[2000];
	
	va_list ap;
	va_start(ap, s);
	vsprintf(buf, s, ap);
	va_end(ap);
	fprintf(stderr,"%s\n", buf);
	terminate(-1);
}

char *strupper(char *s)
{
	char *d = malloc(strlen(s)+1);
	char *p = d;
	
	if (!d)
		die("out of room in strupper");
	while (*p++ = toupper(*s++)) ;
	return d;
}

char *strlower(char *s)
{
	char *d = malloc(strlen(s)+1);
	char *p = d;
	
	if (!d)
		die("out of room in strlower");
	while (*p++ = tolower(*s++)) ;
	return d;
}

int eq(char *a, char *b)
{
	return (strcmp(a, b) == 0);
}

/*
 * higher level send and receive routines
 */

fcb_t *fcb_new(int cnum, int sort)
{
	fcb_t *f = malloc(sizeof(fcb_t));
	if (!f)
		die("no room in fcb_new");
	memset (f, 0, sizeof(fcb_t));
	f->cnum = cnum;
	f->sort = sort;
	f->inq = chain_new();
	f->outq = chain_new();
	return f;
}

void send_text(fcb_t *f, char *s, int l)
{
	cmsg_t *mp;
	mp = cmsg_new(l+1, f->sort, f);
	memcpy(mp->inp, s, l);
	mp->inp += l;
	*mp->inp++ = nl;
	cmsg_send(f->outq, mp, 0);
	f->sp->flags |= SEL_OUTPUT;
}

void send_msg(fcb_t *f, char let, char *s, int l)
{
	cmsg_t *mp;
	int ln;
	int myl = strlen(call)+2+l;

	mp = cmsg_new(myl+4, f->sort, f);
	ln = htonl(myl);
	memcpy(mp->inp, &ln, 4);
	mp->inp += 4;
	*mp->inp++ = let;
	strcpy(mp->inp, call);
	mp->inp += strlen(call);
	*mp->inp++ = '|';
	if (l) {
		memcpy(mp->inp, s, l);
		mp->inp += l;
	}
	*mp->inp = 0;
	cmsg_send(f->outq, mp, 0);
	f->sp->flags |= SEL_OUTPUT;
}

int fcb_handler(sel_t *sp, int in, int out, int err)
{
	fcb_t *f = sp->fcb;
	cmsg_t *mp, *omp;
	
	/* input modes */
	if (in) {
		char *p, buf[MAXBUFL];
		int r;

		/* read what we have into a buffer */
		r = read(f->cnum, buf, MAXBUFL);
		if (r < 0) {
			switch (errno) {
			case EINTR:
			case EINPROGRESS:
			case EAGAIN:
				goto lout;
			default:
				if (f->sort == MSG)
					send_Z = 0;
				ending++;
				return 0;
			}
		} else if (r == 0) {
			if (f->sort == MSG)
				send_Z = 0;
			ending++;
			return 0;
		}

		dbgdump(DBUF, "in ->", buf, r);
		
		/* create a new message buffer if required */
		if (!f->in)
			f->in = cmsg_new(MAXBUFL, f->sort, f);
		mp = f->in;

		switch (f->sort) {
		case TEXT:
			p = buf;
			if (f->echo)
				omp = cmsg_new(3*r, f->sort, f);
			while (r > 0 && p < &buf[r]) {

				/* echo processing */
				if (f->echo) {
					switch (*p) {
					case '\b':
					case 0x7f:
						strcpy(omp->inp, "\b \b");
						omp->inp += strlen(omp->inp);
						break;
					default:
						*omp->inp++ = *p;
					}
				}
				
				/* character processing */
				switch (*p) {
				case '\b':
				case 0x7f:
					if (mp->inp > mp->data)
						mp->inp--;
					++p;
					break;
				default:
					if (*p == nl) {
						if (mp->inp == mp->data)
							*mp->inp++ = ' ';
						*mp->inp = 0;              /* zero terminate it, but don't include it in the length */
						dbgdump(DMSG, "QUEUE TEXT", mp->data, mp->inp-mp->data);
						cmsg_send(f->inq, mp, 0);
						f->in = mp = cmsg_new(MAXBUFL, f->sort, f);
						++p;
					} else {
						if (mp->inp < &mp->data[MAXBUFL])
							*mp->inp++ = *p++;
						else {
							mp->inp = mp->data;
						}
					}
				}
			}
			
			/* queue any echo text */
			if (f->echo) {
				dbgdump(DMSG, "QUEUE ECHO TEXT", omp->data, omp->inp - omp->data);
				cmsg_send(f->outq, omp, 0);
				f->sp->flags |= SEL_OUTPUT;
			}
			
			break;

		case MSG:
			p = buf;
			while (r > 0 && p < &buf[r]) {

				/* build up the size into the likely message length (yes I know it's a short) */
				switch (mp->state) {
				case 0:
				case 1:
					mp->state++;
					break;
				case 2:
				case 3:
					mp->size = (mp->size << 8) | (*p++ & 0xff);
					mp->state++;
					break;
				default:
					if (mp->inp - mp->data < mp->size) {
						*mp->inp++ = *p++;
					} 
					if (mp->inp - mp->data >= mp->size) {
						/* kick it upstairs */
						dbgdump(DMSG, "QUEUE MSG", mp->data, mp->inp - mp->data);
						cmsg_send(f->inq, mp, 0);
						mp = f->in = cmsg_new(MAXBUFL, f->sort, f);
					}
				}
			}
			break;
			
		default:
			die("invalid sort (%d) in input handler", f->sort);
		}
	}
	
	/* output modes */
lout:;
	if (out) {
		int l, r;
		
		if (!f->out) {
			mp = f->out = cmsg_next(f->outq);
			if (!mp) {
				sp->flags &= ~SEL_OUTPUT;
				return 0;
			}
			mp->inp = mp->data;
		}
		l = mp->size - (mp->inp - mp->data);
		if (l > 0) {
			
			dbgdump(DBUF, "<-out", mp->inp, l);
			
			r = write(f->cnum, mp->inp, l);
			if (r < 0) {
				switch (errno) {
				case EINTR:
				case EINPROGRESS:
				case EAGAIN:
					goto lend;
				default:
					if (f->sort == MSG)
						send_Z = 0;
					ending++;
					return;
				}
			} else if (r > 0) {
				mp->inp += r;
			}
		} else if (l < 0) 
			die("got negative length in handler on node");
		if (mp->inp - mp->data >= mp->size) {
			cmsg_callback(mp, 0);
			f->out = 0;
/*			if (is_chain_empty(f->outq))
			sp->flags &= ~SEL_OUTPUT; */
		}
	}
lend:;
	return 0;
}

/*
 * things to do with initialisation
 */

void initargs(int argc, char *argv[])
{
	int i, c, err = 0;

	while ((c = getopt(argc, argv, "x:")) > 0) {
		switch (c) {
		case 'x':
			dbginit("client");
			dbgset(atoi(optarg));
			break;
		default:
			++err;
			goto lerr;
		}
	}

lerr:
	if (err) {
		die("usage: client [-x nn] <call>|login [local|telnet|ax25]");
	}
	
	if (optind < argc) {
		call = strupper(argv[optind]);
		if (eq(call, "LOGIN"))
			die("login not implemented (yet)");
		++optind;
	}
	if (!call)
		die("Must have at least a callsign (for now)");

	if (optind < argc) {
		connsort = strlower(argv[optind]);
		if (eq(connsort, "telnet") || eq(connsort, "local")) {
			nl = '\n';
			echo = 1;
		} else if (eq(connsort, "ax25")) {
			nl = '\r';
			echo = 0;
		} else {
			die("2nd argument must be \"telnet\" or \"ax25\" or \"local\"");
		}
	} else {
		connsort = "local";
		nl = '\n';
		echo = 1;
	}
}

void connect_to_node()
{
	struct hostent *hp, *gethostbyname();
	struct sockaddr_in server;
	int nodef;
	sel_t *sp;
				
	if ((hp = gethostbyname(node_addr)) == 0) 
		die("Unknown host tcp host %s for printer", node_addr);

	memset(&server, 0, sizeof server);
	server.sin_family = AF_INET;
	memcpy(&server.sin_addr, hp->h_addr, hp->h_length);
	server.sin_port = htons(node_port);
						
	nodef = socket(AF_INET, SOCK_STREAM, 0);
	if (nodef < 0) 
		die("Can't open socket to %s port %d (%d)", node_addr, node_port, errno);

	if (connect(nodef, (struct sockaddr *) &server, sizeof server) < 0) {
		die("Error on connect to %s port %d (%d)", node_addr, node_port, errno);
	}
	node = fcb_new(nodef, MSG);
	node->sp = sel_open(nodef, node, "Msg System", fcb_handler, MSG, SEL_INPUT);
	
}

/*
 * things to do with going away
 */

void term_timeout(int i)
{
	/* none of this is going to be reused so don't bother cleaning up properly */
	if (in)
		tcsetattr(0, TCSANOW, &in->t);
	if (node) {
		close(node->cnum);
	}
	exit(i);
}

void terminate(int i)
{
	if (send_Z && call) {
		send_msg(node, 'Z', "", 0);
	}
	
	signal(SIGALRM, term_timeout);
	alarm(10);
	
	while ((in && !is_chain_empty(in->outq)) ||
		   (node && !is_chain_empty(node->outq))) {
		sel_run();
	}
	if (in)
		tcsetattr(0, TCSANOW, &in->t);
	if (node) 
		close(node->cnum);
	exit(i);
}

/*
 * things to do with ongoing processing of inputs
 */

void process_stdin()
{
	cmsg_t *mp = cmsg_next(in->inq);
	if (mp) {
		dbg(DMSG, "MSG size: %d", mp->size);
	
		if (mp->size > 0 && mp->inp > mp->data) {
			send_msg(node, 'I', mp->data, mp->size);
		}
		cmsg_callback(mp, 0);
	}
}

void process_node()
{
	cmsg_t *mp = cmsg_next(node->inq);
	if (mp) {
		dbg(DMSG, "MSG size: %d", mp->size);
	
		if (mp->size > 0 && mp->inp > mp->data) {
			char *p = strchr(mp->data, '|');
			if (p)
				p++;
			switch (mp->data[0]) {
			case 'Z':
				send_Z = 0;
				ending++;
				return;
			case 'E':
				if (isdigit(*p))
					in->echo = *p - '0';
				break;
			case 'D':
				if (p) {
					int l = mp->inp - (unsigned char *) p;
					send_text(in, p, l);
			}
				break;
			default:
				break;
			}
		}
		cmsg_callback(mp, 0);
	}
}

/*
 * the program itself....
 */

main(int argc, char *argv[])
{
	initargs(argc, argv);
	sel_init(10, 0, 10000);

	signal(SIGHUP, SIG_IGN);

	signal(SIGINT, terminate);
	signal(SIGQUIT, terminate);
	signal(SIGTERM, terminate);
	signal(SIGPWR, terminate);

	/* connect up stdin, stdout and message system */
	in = fcb_new(0, TEXT);
	in->sp = sel_open(0, in, "STDIN", fcb_handler, TEXT, SEL_INPUT);
	if (tcgetattr(0, &in->t) < 0) 
		die("tcgetattr (%d)", errno);
	{
		struct termios t = in->t;
		t.c_lflag &= ~(ECHO|ECHONL|ICANON);
		if (tcsetattr(0, TCSANOW, &t) < 0) 
			die("tcsetattr (%d)", errno);
		in->echo = echo;
	}
	connect_to_node();

	/* tell the cluster who I am */
	send_msg(node, 'A', connsort, strlen(connsort));
	
	/* main processing loop */
	while (!ending) {
		sel_run();
		if (!ending) {
			process_stdin();
			process_node();
		}
	}
	terminate(0);
}






