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
#include <regex.h>

#include "sel.h"
#include "cmsg.h"
#include "debug.h"

#define TEXT 1
#define MSG 2
#define MAXBUFL 1024

#ifndef MAXPATHLEN 
#define MAXPATHLEN 256
#endif

#define DEFPACLEN 128
#define MAXPACLEN 236
#define MAXCALLSIGN 9

#define DBUF 1
#define DMSG 2

typedef struct 
{
	int cnum;					/* the connection number */
	int sort;					/* the type of connection either text or msg */
	cmsg_t *in;					/* current input message being built up */
	cmsg_t *out;				/* current output message being sent */
	cmsg_t *obuf;				/* current output being buffered */
	reft *inq;					/* input queue */
	reft *outq;					/* output queue */
	sel_t *sp;					/* my select fcb address */
	struct termios t;			/* any termios associated with this cnum */
	char echo;					/* echo characters back to this cnum */
	char t_set;					/* the termios structure is valid */
	char buffer_it;				/* buffer outgoing packets for paclen */
} fcb_t;

typedef struct 
{
	char *in;
	regex_t *regex;
} myregex_t;


char *node_addr = "localhost";	/* the node tcp address, can be overridden by DXSPIDER_HOST */
int node_port = 27754;			/* the tcp port of the node at the above address can be overidden by DXSPIDER_PORT*/
char *call;						/* the caller's callsign */
char *connsort;					/* the type of connection */
fcb_t *in;						/* the fcb of 'stdin' that I shall use */
fcb_t *node;					/* the fcb of the msg system */
char nl = '\n';					/* line end character */
char ending = 0;				/* set this to end the program */
char send_Z = 1;				/* set a Z record to the node on termination */
char echo = 1;					/* echo characters on stdout from stdin */
char int_tabs = 0;				/* interpret tabs -> spaces */
char *root = "/spider";         /* root of data tree, can be overridden by DXSPIDER_ROOT  */
int timeout = 60;				/* default timeout for logins and things */
int paclen = DEFPACLEN;			/* default buffer size for outgoing packets */
int tabsize = 8;				/* default tabsize for text messages */

myregex_t iscallreg[] = {		/* regexes to determine whether this is a reasonable callsign */
	{
		"^[A-Z]+[0-9]+[A-Z]+[1-9]?$", 0	               /* G1TLH G1TLH1 */
	},
	{
		"^[0-9]+[A-Z]+[0-9]+[A-Z]+[1-9]?$", 0          /* 2E0AAA 2E0AAA1 */
	},
	{
		"^[A-Z]+[0-9]+[A-Z]+-[1-9]$", 0                /* G1TLH-2 */
	},
	{
		"^[0-9]+[A-Z]+[0-9]+[A-Z]+-[1-9]$", 0          /* 2E0AAA-2 */
	},
	{
		"^[A-Z]+[0-9]+[A-Z]+-1[0-5]$", 0               /* G1TLH-11 */
	},
	{
		"^[0-9]+[A-Z]+[0-9]+[A-Z]+-1[0-5]$", 0         /* 2E0AAA-11 */
	},
	{
		0, 0
	}
};

void terminate(int);

/*
 * utility routines - various
 */

void die(char *s, ...)
{
	char buf[2000];
	
	va_list ap;
	va_start(ap, s);
	vsnprintf(buf, sizeof(buf)-1, s, ap);
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

int xopen(char *dir, char *name, int mode)
{
	char fn[MAXPATHLEN+1];
	snprintf(fn, MAXPATHLEN, "%s/%s/%s", root, dir, name);
	return open(fn, mode);
}

int iscallsign(char *s)
{
	myregex_t *rp;

	if (strlen(s) > MAXCALLSIGN)
		return 0;
	
	for (rp = iscallreg; rp->in; ++rp) {
		if (regexec(rp->regex, s, 0, 0, 0) == 0)
			return 1;
	}
	return 0;
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

void flush_text(fcb_t *f)
{
	if (f->obuf) {
		cmsg_send(f->outq, f->obuf, 0);
		f->sp->flags |= SEL_OUTPUT;
		f->obuf = 0;
	}
}

void send_text(fcb_t *f, char *s, int l)
{
	cmsg_t *mp;
	char *p;
	
	if (f->buffer_it && f->obuf) {
		mp = f->obuf;
	} else {
		f->obuf = mp = cmsg_new(paclen+1, f->sort, f);
	}

	/* remove trailing spaces  */
	while (l > 0 &&isspace(s[l-1]))
		--l;

	for (p = s; p < s+l; ) {
		if (mp->inp >= mp->data + paclen) {
			flush_text(f);
			f->obuf = mp = cmsg_new(paclen+1, f->sort, f);
		}
		*mp->inp++ = *p++;
	}
	if (mp->inp >= mp->data + paclen) {
		flush_text(f);
		f->obuf = mp = cmsg_new(paclen+1, f->sort, f);
	}
	*mp->inp++ = nl;
	if (!f->buffer_it)
		flush_text(f);
}

void send_msg(fcb_t *f, char let, char *s, int l)
{
	cmsg_t *mp;
	int ln;
	int myl = strlen(call)+2+l;

	mp = cmsg_new(myl+4+1, f->sort, f);
	ln = htonl(myl);
	memcpy(mp->inp, &ln, 4);
	mp->inp += 4;
	*mp->inp++ = let;
	strcpy(mp->inp, call);
	mp->inp += strlen(call);
	*mp->inp++ = '|';
	if (l > 0) {
		memcpy(mp->inp, s, l);
		mp->inp += l;
	}
	*mp->inp = 0;
	cmsg_send(f->outq, mp, 0);
	f->sp->flags |= SEL_OUTPUT;
}

/*
 * the callback (called by sel_run) that handles all the inputs and outputs
 */

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
			f->in = cmsg_new(MAXBUFL+1, f->sort, f);
		mp = f->in;

		switch (f->sort) {
		case TEXT:
			p = buf;
			if (f->echo)
				omp = cmsg_new(3*r+1, f->sort, f);
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
				case '\t':
					if (int_tabs) {
						memset(mp->inp, ' ', tabsize);
						mp->inp += tabsize;
						++p;
					} else {
						*mp->inp++ = *p++;
					}
					break;
				case '\b':
				case 0x7f:
					if (mp->inp > mp->data)
						mp->inp--;
					++p;
					break;
				default:
					if (nl == '\n' && *p == '\r') {   /* ignore \r in telnet mode (ugh) */
						p++;
					} else if (*p == nl) {
						if (mp->inp == mp->data)
							*mp->inp++ = ' ';
						*mp->inp = 0;              /* zero terminate it, but don't include it in the length */
						dbgdump(DMSG, "QUEUE TEXT", mp->data, mp->inp-mp->data);
						cmsg_send(f->inq, mp, 0);
						f->in = mp = cmsg_new(MAXBUFL+1, f->sort, f);
						++p;
					} else {
						if (mp->inp < &mp->data[MAXBUFL-8])
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
					if (mp->size > MAXBUFL)
						die("Message size too big from node (%d > %d)", mp->size, MAXBUFL);
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
						mp = f->in = cmsg_new(MAXBUFL+1, f->sort, f);
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

	while ((c = getopt(argc, argv, "h:p:x:")) > 0) {
		switch (c) {
		case 'h':
			node_addr = optarg;
			break;
		case 'l':
			paclen = atoi(optarg);
			if (paclen < 80)
				paclen = 80;
			if (paclen > MAXPACLEN)
				paclen = MAXPACLEN;
			break;
		case 'p':
			node_port = atoi(optarg);
			break;
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
		die("usage: client [-x n|-h<host>|-p<port>|-l<paclen>] <call>|login [local|telnet|ax25]");
	}
	
	if (optind < argc) {
		call = strupper(argv[optind]);
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

	/* this is kludgy, but hey so is the rest of this! */
	if (!eq(connsort, "ax25") && paclen == DEFPACLEN) {
		paclen = MAXPACLEN;
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
	if (in && in->t_set)
		tcsetattr(0, TCSANOW, &in->t);
	if (node) {
		close(node->cnum);
	}
	exit(i);
}

void terminate(int i)
{
	if (node && send_Z && call) {
		send_msg(node, 'Z', "", 0);
	}
	
	signal(SIGALRM, term_timeout);
	alarm(10);
	
	while ((in && !is_chain_empty(in->outq)) ||
		   (node && !is_chain_empty(node->outq))) {
		sel_run();
	}
	if (in && in->t_set)
		tcsetattr(0, TCSADRAIN, &in->t);
	if (node) 
		close(node->cnum);
	exit(i);
}

void login_timeout(int i)
{
	write(0, "Timed Out", 10);
	write(0, &nl, 1);
	sel_run();					/* force a coordination */
	if (in && in->t_set)
		tcsetattr(0, TCSANOW, &in->t);
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
			case 'B':
				if (isdigit(*p))
					in->buffer_it = *p - '0';
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
	} else {
		flush_text(in);
	}
}

/*
 * the program itself....
 */

main(int argc, char *argv[])
{
	/* set up environment */
	{
		char *p = getenv("DXSPIDER_ROOT");
		if (p)
			root = p;
		p = getenv("DXSPIDER_HOST");
		if (p)
			node_addr = p;
		p = getenv("DXSPIDER_PORT");
		if (p)
			node_port = atoi(p);
		p = getenv("DXSPIDER_PACLEN");
		if (p) {
			paclen = atoi(p);
			if (paclen < 80)
				paclen = 80;
			if (paclen > MAXPACLEN)
				paclen = MAXPACLEN;
		}
	}
	
	/* get program arguments, initialise stuff */
	initargs(argc, argv);
	sel_init(10, 0, 10000);

	/* trap signals */
	signal(SIGHUP, SIG_IGN);
	signal(SIGINT, terminate);
	signal(SIGQUIT, terminate);
	signal(SIGTERM, terminate);
#ifdef SIGPWR
	signal(SIGPWR, terminate);
#endif

	/* compile regexes for iscallsign */
	{
		myregex_t *rp;
		for (rp = iscallreg; rp->in; ++rp) {
			regex_t reg;
			int r = regcomp(&reg, rp->in, REG_EXTENDED|REG_ICASE|REG_NOSUB);
			if (r)
				die("regcomp returned %d for '%s'", r, rp->in);
			rp->regex = malloc(sizeof(regex_t));
			if (!rp->regex)
				die("out of room - compiling regexes");
			*rp->regex = reg;
		}
	}
	
	/* is this a login? */
	if (eq(call, "LOGIN")) {
		char buf[MAXPACLEN+1];
		int r;
		int f = xopen("data", "issue", 0);
		if (f > 0) {
			while ((r = read(f, buf, paclen)) > 0) {
				if (nl != '\n') {
					char *p;
					for (p = buf; p < &buf[r]; ++p) {
						if (*p == '\n')
							*p = nl;
					}
				}
				write(0, buf, r);
			}
			close(f);
		}
		signal(SIGALRM, login_timeout);
		alarm(timeout);
		write(0, "login: ", 7);
		r = read(0, buf, 20);
		if (r <= 0)
			die("No login or error (%d)", errno);
		signal(SIGALRM, SIG_IGN);
		alarm(0);
		while (r > 0) {
			if (buf[r-1] == ' ' || buf[r-1] == '\r' || buf[r-1] == '\n')
				--r;
			else
				break;
		}
		buf[r] = 0;
		call = strupper(buf);
	}

	/* check the callsign */
	if (!iscallsign(call)) {
		die("Sorry, %s isn't a valid callsign", call);
	}
	
	/* connect up stdin */
	in = fcb_new(0, TEXT);
	in->sp = sel_open(0, in, "STDIN", fcb_handler, TEXT, SEL_INPUT);
	if (tcgetattr(0, &in->t) < 0) {
		echo = 0;
		in->t_set = 0;
	} else {
		struct termios t = in->t;
		t.c_lflag &= ~(ECHO|ECHONL|ICANON);
		if (tcsetattr(0, TCSANOW, &t) < 0) 
			die("tcsetattr (%d)", errno);
		in->echo = echo;
		in->t_set = 1;
	}
	in->buffer_it = 1;

	/* connect up node */
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






