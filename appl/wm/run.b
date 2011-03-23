implement WmRun;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
	draw: Draw;
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "names.m";
	names: Names;
include "plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;
include "wait.m";
	wait: Wait;
include "readdir.m";
	readdir: Readdir;
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "keyboard.m";
	kb: Keyboard;

include "run/complete.b";
include "run/edit.b";
include "run/list.b";

WmRun: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

dflag: int;
plumbed: int;

Msingle, Msplit2, Msplit3: con iota;
splitmode := Msplit2;

# for input entry
Eesc, Einsert, Ectlx: con iota;
editmode := Einsert;

edithist: ref Link[ref Cmd];  # initially nil
editorig: string;  # text for new command before walking history
editorigpos: int;  # cursor in editorig

keyeditorig: ref Str;		# state before (potential) change
keyeditprev,			# previous contents, for 'u', most recent on hd
keyeditnext: list of ref Str;	# next contents, for '^r'

keys: ref Str;     # edit entry's vi command so far
prevkeys: ref Str; # previous command, for repeat with '.'
editbuf: string;   # buffer for deletions, yank & paste

showhist := 0;	   # whether to show multiple commands, only for Msingle
showin := 0;       # whether to show in window (only for Msplit2, Msplit3)
showcolors := 1;   # whether tags have colors

showcomplete := 0; # whether completion frame is currently shown
textfocus := 1;    # text frame with focus, outerr by default

lastmouse: int;    # last mouse buttons
lastb1, lastb2, lastb3: string;  # text widget index

# on command finish, status/exception goes here
statusc: chan of string;
exc: chan of string;

# threads without normal stderr send here
warnc: chan of string;

# all commands have file2chan's for fd 0-2 and send them on these channels to alt in init.
inc: chan of (ref Cmd, (int, int, int, Sys->Rread));
outc,
errc: chan of (ref Cmd, (int, array of byte, int, Sys->Rwrite));
inpending,
outpending,
errpending: array of byte;  # partial utf-8 bytes to write to text widget later

reads: ref List[ref Read];	# reads for stdin
text: ref List[array of byte];	# data to write to stdin

cmdgen: int;  # unique/sequence number for commands
history: ref List[ref Cmd]; # commands in history.  currently executing is history.last
curcmd: ref Link[ref Cmd];  # command currently visible
runpid: int;  # pid of history.last, or 0 when none

top: ref Tk->Toplevel;
wmctl: chan of string;
drawcontext: ref Draw->Context;
shcontext: ref Sh->Context;

Read: adt {
	count:	int;
	rc:	Sys->Rread;
};

Tin, Tout, Terr, Tcmd, Tstatus, Tex, Texit, Tok: con iota;  # Rw.t, tagstrs
tagstrs := array[] of {"in", "out", "err", "cmd", "status", "status", "status", "ok"};
Rw: adt {
	t:	int;
	s:	string;
};
Cmd: adt {
	gen:	int;     # unique gen for cmd
	f:	array of ref Sys->FileIO;  # 0-2
	pids:	array of int;  # 0-2
	wd:	string;  # workdir at end of command
	cmd:	string;  # command, always set
	busy:	int;	 # whether not yet finished
	status:	string;  # return status, if no longer busy
	ex:	string;  # exception raised or thread exit, if no longer busy
	l:	list of ref Rw;  # hd is most recent, includes cmd,status,ex,ok
};

textwidgets := array[] of {"in", "outerr", "err"};

tkcmds0 := array[] of {
"frame .t",
"frame .t.in",
"frame .t.outerr",
"frame .t.err",

"text .t.in.t		-fg white -bg black -selectforeground black -selectbackground white -yscrollcommand {.t.in.s set}",
"text .t.outerr.t	-fg white -bg black -selectforeground black -selectbackground white -yscrollcommand {.t.outerr.s set}",
"text .t.err.t		-fg white -bg black -selectforeground black -selectbackground white -yscrollcommand {.t.err.s set}",

"bind .t.in.t		<Control-t> {focus .e.edit}",
"bind .t.outerr.t	<Control-t> {focus .e.edit}",
"bind .t.err.t		<Control-t> {focus .e.edit}",

"scrollbar .t.in.s	-command {.t.in.t yview}",
"scrollbar .t.outerr.s	-command {.t.outerr.t yview}",
"scrollbar .t.err.s	-command {.t.err.t yview}",

"pack .t.in.s		-fill y -side left",
"pack .t.outerr.s	-fill y -side left",
"pack .t.err.s		-fill y -side left",

"pack .t.in.t		-fill both -expand 1 -side right",
"pack .t.outerr.t	-fill both -expand 1 -side right",
"pack .t.err.t		-fill both -expand 1 -side right",

"frame .c",
"text .c.complete	-yscrollcommand {.c.s set}",
"scrollbar .c.s		-command {.c.complete yview}",
"pack .c.s -fill y -side left",
"pack .c.complete -fill both -expand 1 -side right",

"frame .s",
"label .s.editmode	-width 1w",
"label .s.splitmode	-width 1w",
"label .s.showin	-width 1w",
"label .s.showhist	-width 1w",
"label .s.showcolors	-width 1w",
"label .s.pad1		-width 1w",
"label .s.f0		-fg green -width 1w",
"label .s.f1		-fg green -width 1w",
"label .s.f2		-fg green -width 1w",
"label .s.pad2		-width 1w",
"label .s.status	-width 20w",
"label .s.pad3		-width 1w",
"label .s.gen		-width 5w",
"label .s.pad4		-width 1w -text {: }",
"label .s.cmd",
"pack .s.editmode .s.splitmode .s.showin .s.showhist .s.showcolors .s.pad1 .s.f0 .s.f1 .s.f2 .s.pad2 .s.status .s.pad3 .s.gen .s.pad4 .s.cmd -side left",

"frame .e",
"label .e.mode	-width 1w -text { }",
"entry .e.edit",
"bind .e.edit	{<Key-\t>} {send edit tab}",
"bind .e.edit	<Key-\u007f> {send edit del}",
"bind .e.edit	<Control-n> {send edit next}",
"bind .e.edit	<Control-p> {send edit prev}",
"bind .e.edit	<Control-x> {send edit x}",
"bind .e.edit	<Control-d> {send edit eof}",
"bind .e.edit	<Control-r> {send key %K}",
"bind .e.edit	<Key> {send key %K}",
"pack .e.mode -side left",
"pack .e.edit -fill x -expand 1 -side right",

"pack .t.outerr -fill both -expand 1",
"pack .t -fill both -expand 1",
"pack .s -fill x",
"pack .e -fill x",

"focus .e.edit",
"pack propagate . 0",
". configure -width 80w -height 35h",
};

# additional binds, needing keyboard.m
tkbinds()
{
	tkcmd(sprint("bind .e.edit <Key-%c> {send edit pgup}", kb->Pgup));
	tkcmd(sprint("bind .e.edit <Key-%c> {send edit pgdown}", kb->Pgdown));
	tkcmd(sprint("bind .e.edit <Key-%c> {send edit esc}", kb->Esc));

	for(l := list of {"in", "outerr", "err"}; l != nil; l = tl l)
		for(b := list of {1, 2, 3}; b != nil; b = tl b) {
			tkcmd(sprint("bind .t.%s.t <ButtonPress-%d> +{send mouse %%s %%W @%%x,%%y}", hd l, hd b));
			tkcmd(sprint("bind .t.%s.t <ButtonRelease-%d> +{send mouse %%s %%W @%%x,%%y}", hd l, hd b));
		}
}

tags := array[] of {"in", "out", "err", "cmd", "status", "ok"};
tagcolors := array[] of {"#0000ff", "white", "orange", "lime", "red", "yellow"};
tktags(on: int)
{
	for(i := 0; i < len textwidgets; i++) {
		w := sprint(".t.%s.t", textwidgets[i]);
		for(j := 0; j < len tags; j++) {
			c := "white";
			if(on)
				c = tagcolors[j];
			tkcmd(sprint("%s tag configure %s -fg %s -bg black", w, tags[j], c));
		}
		tkcmd(sprint("%s tag raise sel", w));
	}
}

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	if(ctxt == nil)
		fail("no window context");
	drawcontext = ctxt;
	draw = load Draw Draw->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	names = load Names Names->PATH;
	plumbmsg = load Plumbmsg Plumbmsg->PATH;
	wait = load Wait Wait->PATH;
	wait->init();
	readdir = load Readdir Readdir->PATH;
	sh = load Sh Sh->PATH;
	sh->initialise();
	shcontext = Context.new(ctxt);
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	sys->pctl(Sys->NEWPGRP|Sys->FORKENV|Sys->FORKNS|Sys->FORKFD, nil);

	plumbed = plumbmsg->init(1, nil, 512) >= 0;

	# keep usage in sync with new()
	arg->init(args);
	arg->setusage(arg->progname()+" [-d] [-123Chi] [cmd ...]");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	dflag++;
		'1' =>	splitmode = Msingle; textfocus = 0;
		'2' =>	splitmode = Msplit2;
		'3' =>	splitmode = Msplit3;
		'C' =>	showcolors = 0;
		'h' =>	showhist = 1;
		'i' =>	showin = 1;
		* =>	arg->usage();
		}
	args = arg->argv();

	tkclient->init();
	(top, wmctl) = tkclient->toplevel(ctxt, "", "run "+workdir(), Tkclient->Appl);

	history = history.new();
	reads = reads.new();
	text = text.new();
	keyeditorig = ref Str ("", 0, 0, 0);

	if(sys->bind("#s", "/chan", Sys->MBEFORE) < 0)
		fail(sprint("bind: %r"));
	nopermfile := "wmrun.noperm."+string pid();
	nopermfio := sys->file2chan("/chan", nopermfile);
	if(nopermfio == nil)
		fail(sprint("file2chan: %r"));
	nopermfile = "/chan/"+nopermfile;
	d := sys->nulldir;
	d.mode = 0;
	if(sys->wstat(nopermfile, d) < 0)
		fail(sprint("wstat %q: %r", nopermfile));
	if(sys->bind(nopermfile, "/dev/cons", Sys->MREPL) < 0
		|| sys->bind(nopermfile, "/dev/consctl", Sys->MREPL) < 0)
		fail(sprint("bind cons,consctl: %r"));

	statusc = chan of string;
	exc = chan of string;
	inc = chan of (ref Cmd, (int, int, int, Sys->Rread));
	outc = chan of (ref Cmd, (int, array of byte, int, Sys->Rwrite));
	errc = chan of (ref Cmd, (int, array of byte, int, Sys->Rwrite));

	warnc = chan of string;
	spawn warner();

	waitfd := sys->open(sprint("/prog/%d/wait", pid()), Sys->OREAD);
	if(waitfd == nil)
		fail(sprint("open: %r"));
	(nil, waitc) := wait->monitor(waitfd);
	waitfd = nil;

	editc := chan of string;
	keyc := chan of string;
	mousec := chan of string;
	tk->namechan(top, editc, "edit");
	tk->namechan(top, keyc, "key");
	tk->namechan(top, mousec, "mouse");
	tkcmds(tkcmds0);
	tkbinds();
	tktags(showcolors);
	tkseteditmode();
	tksplitmodeset(splitmode);
	tksetshowin();
	tksetshowhist();
	tksetshowcolors();
	tktextfocus(textfocus);

	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	if(args == nil)
		start(sprint("{echo ..; ls} | mc -c %d", tktextwidth()));
	else
		start(str->quoted(args));

	for(;;) alt {
	s := <-top.ctxt.kbd =>
		tk->keyboard(top, s);

	s := <-top.ctxt.ptr =>
		tk->pointer(top, *s);

	s := <-top.ctxt.ctl or
	s = <-top.wreq or
	s = <-wmctl =>
		tkclient->wmctl(top, s);

	s := <-editc =>
		cmd(s);
		tkup();

	s := <-keyc =>
		key(str->toint(s, 16).t0);
		tkup();

	s := <-mousec =>
		mouse(s);
		tkup();

	s := <-statusc =>
		if(s == nil)
			progdone(Tok, s);
		else
			progdone(Tstatus, s);
		tkup();

	s := <-exc =>
		progdone(Tex, s);
		tkup();

	(pid, nil, status) := <-waitc =>
		if(runpid == pid) {
			if(status == nil)
				status = "exit";
			progdone(Texit, status);
			tkup();
		}

	(cmd, (nil, count, nil, rc)) := <-inc =>
		if(rc == nil) {
			cmdclearfd(cmd, 0);
		} else if(cmd != history.last.e) {
			rc <-= (array[0] of byte, nil);
		} else {
			reads.append(ref Read (count, rc));
			respondreads(cmd);
			tkup();
		}

	(cmd, (nil, data, nil, wc)) := <-outc =>
		if(wc == nil) {
			cmdclearfd(cmd, 1);
		} else {
			s: string;
			(s, outpending) = utf(outpending, data);
			cmdadd(cmd, Tout, s);
			wc <-= (len data, nil);
			tkup();
		}

	(cmd, (nil, data, nil, wc)) := <-errc =>
		if(wc == nil) {
			cmdclearfd(cmd, 2);
		} else {
			s: string;
			(s, errpending) = utf(errpending, data);
			cmdadd(cmd, Terr, string data);
			wc <-= (len data, nil);
			tkup();
		}
	}
}

# a is leftover, b is new data.  make utf-8 string, and return remaining trailing data
utf(a, b: array of byte): (string, array of byte)
{
	if(len a == 0)
		c := b;
	else {
		c = array[len a+len b] of byte;
		c[:] = a;
		c[len a:] = b;
	}
	n := sys->utfbytes(c, len c);
	s := string c[:n];
	r := c[n:];
	if(len r == 0)
		r = nil;
	return (s, r);
}

cmdclearfd(cmd: ref Cmd, f: int)
{
	kill(cmd.pids[f]);
	cmd.f[f] = nil;
	tklabel(".s.f"+string f, "");
	if(cmd.f[0] == nil && cmd.f[1] == nil && cmd.f[2] == nil)
		tkup();  # do 1 update when prog is done
}

# for threads that got new fd table
warner()
{
	for(;;)
		warn(<-warnc);
}

# could do more with mouse movements, e.g. chording
mouse(s: string)
{
	(nil, l) := sys->tokenize(s, " ");
	b := int hd l;
	w := hd tl l;
	coord := hd tl tl l;
	pos := tkcmd(sprint("%s index %s", w, coord));
	say(sprint("lastmouse %d, b %d, widget %s, coord %s, pos %s", lastmouse, b, w, coord, pos));
	if(str->prefix("!", pos))
		return;

	b1: con 1<<0;
	b2: con 1<<1;
	b3: con 1<<2;

	if((lastmouse & b3) && (~b & b3)) {
		t := tkcmd(w+sprint(" get {%s linestart} {%s lineend}", pos, pos));
		o := int str->splitstrr(pos, ".").t1;
		for(si := o; si > 0 && !str->in(t[si-1], Whitespace); si--)
			{}
		for(ei := o; ei < len t && !str->in(t[ei], Whitespace); ei++)
			{}
		path := t[si:ei];
		if(si != ei) {
			dir := path;
			if(!curcmd.e.busy && !isabs(path) && curcmd.e.wd != workdir())
				dir = curcmd.e.wd+"/"+dir;
			(ok, d) := sys->stat(dir);
			if(ok >= 0 && (d.mode & Sys->DMDIR)) {
				if(runpid)
					spawn new(list of {"sh", "-c", sprint("load std; cd %q && {echo ..; ls} | mc", dir)});
				else
					start(sprint("load std; cd %q && {echo ..; ls} | mc -c %d", dir, tktextwidth()));
			} else {
				if(!plumb(path) && path[len path-1] == ':')
					plumb(path[:len path-1]);
			}
		}
	}

	if(b & b1) lastb1 = pos;
	if(b & b2) lastb2 = pos;
	if(b & b3) lastb3 = pos;
	lastmouse = b;
}

plumb(s: string): int
{
	if(!plumbed)
		return 0;
	# for old commands, we plumb from the dir the command finished in
	if(curcmd != nil && !curcmd.e.busy)
		wd := curcmd.e.wd;
	else
		wd = workdir();
	m := ref Msg ("WmRun", "", wd, "text", "", array of byte s);
	return m.send() >= 0;
}

cmd(s: string)
{
	if(s != "tab")
		tkcompletehide();
	case s {
	"tab" =>
		e := tkeditstr();
		si := (ref *e).rskipcl(Nonwhitespace);
		ei := (ref *e).skipcl(Nonwhitespace);
		if(si != ei)
			complete(e.s, si, ei);
	"next" =>
		if(curcmd != nil && curcmd.next != nil) {
			curcmd = curcmd.next;
			redraw();
		}
	"prev" =>
		if(curcmd != nil && curcmd.prev != nil) {
			curcmd = curcmd.prev;
			redraw();
		}
	"eof" =>
		if(!runpid)
			quit();
		if(curcmd == nil)
			break;
		text.append(array of byte "");
		respondreads(curcmd.e);
	"del" =>
		if(runpid)
			killprog();
	"pgup" =>
		tkcmd(sprint(".t.%s.t yview scroll -1 pages", textwidgets[textfocus]));
	"pgdown" =>
		tkcmd(sprint(".t.%s.t yview scroll 1 pages", textwidgets[textfocus]));
	"esc" =>
		case editmode {
		Einsert =>
			recordundo();
			editmode = Eesc;
			tkseteditmode();
		Ectlx =>
			editmode = Einsert;
			tkseteditmode();
		Eesc =>
			keys = nil;
		}
	"x" =>
		case editmode {
		Ectlx =>
			{}
		Eesc or
		Einsert =>
			keys = nil;
			editmode = Ectlx;
			tkseteditmode();
		}
	* =>
		warn(sprint("other cmd %q", s));
	}
}

progdone(t: int, s: string)
{
	runpid = 0;
	cmdadd(history.last.e, t, s);
	history.last.e.wd = workdir();
	reads = reads.new();
	text = text.new();
	tksetmode();
}

killprog()
{
	killgrp(runpid);
	progdone(Tstatus, "killed");
}

new(argv: list of string)
{
	if(showin)
		argv = "-i"::argv;
	if(showhist)
		argv = "-h"::argv;
	if(!showcolors)
		argv = "-C"::argv;
	argv = sprint("-%c", splitmode+'1')::argv;
	if(dflag)
		argv = "-d"::argv;
	argv = "wm/run"::argv;
	sh->run(drawcontext, argv);
}

ctlx(c: int)
{
	case c {
	'p' =>
		s := tkeditstr().s;
		if(plumb(s))
			tkedit(0, len s, "", 0);
	'n' =>
		s := tkeditstr().s;
		tkedit(0, len s, "", 0);
		if(s != nil)
			argv := list of {"sh", "-c", s};
		spawn new(argv);
	'z' =>
		if(curcmd == nil)
			break;
		while(history.first != nil && history.first != curcmd)
			history.takefirst();
	'r' =>
		if(runpid)
			break;
		text.append(array of byte tktextsel());
		text.append(array of byte "");
		start("sh -n");
	'\n' =>
		if(runpid)
			break;
		x := tkeditstr();
		if(x.s == nil)
			break;
		tkedit(0, len x.s, "", 0);
		text.append(array of byte tktextsel());
		text.append(array of byte "");
		start(x.s);
	'c' =>
		showcolors = !showcolors;
		tktags(showcolors);
		tksetshowcolors();
	'x' =>	dflag = !dflag;
	'0' =>
		curcmd = history.first;
		if(curcmd != nil)
			redraw();
	'$' =>
		curcmd = history.last;
		if(curcmd != nil)
			redraw();
	'k' =>
		if(runpid)
			killprog();
	'1' to '3' =>
		tksplitmodeset(c-'1');
	'!' =>
		if(splitmode > Msingle && showin)
			tktextfocus(0);
	'@' =>
		if(splitmode >= Msplit2)
			tktextfocus(1);
	'#' =>
		if(splitmode >= Msplit3)
			tktextfocus(2);
	'i' =>
		if(splitmode == Msplit2 || splitmode == Msplit3) {
			if(showin)
				tkcmd("pack forget .t.in");
			else
				tkcmd("pack .t.in -before .t.outerr -fill both -expand 1");
			showin = !showin;
			tksetshowin();
		}
	'h' =>
		showhist = !showhist;
		tksetshowhist();
		redraw();
	'l' =>
		redraw();
	'.' =>
		if(!runpid)
			start(sprint("{echo ..; ls} | mc -c %d", tktextwidth()));
	'F' =>
		if(!runpid)
			start(sprint("find -f . | mc -c %d", tktextwidth()));
	'f' =>
		if(!runpid)
			start(sprint("find -f -T .hg -N '*.dis' -N '*.sbl' . | mc -c %d", tktextwidth()));
	'd' =>
		if(!runpid)
			start(sprint("find -F -T .hg . | mc -c %d", tktextwidth()));
	* =>
		say("bad ctlx command");
	}
	editmode = Einsert;
	tkseteditmode();
}

recordundo()
{
	e := tkeditstr();
	if(e.s != keyeditorig.s) {
		keyeditprev = keyeditorig::keyeditprev;
		keyeditnext = nil;
	}
}

key(c: int)
{
	say(sprint("key, c %c, editmode %d", c, editmode));
	e := tkeditstr();

	if(c == '\n' && (editmode == Einsert || editmode == Eesc)) {
		tkcompletehide();
		if(e.s == nil)
			return;
		tkedit(0, len e.s, "", 0);
		if(runpid) {
			text.append(array of byte (e.s+"\n"));
			respondreads(curcmd.e);
		} else
			start(e.s);
		editmode = Einsert;
		tkseteditmode();
		return;
	}

	if(editmode == Einsert) {
		tkcmd(".e.edit delete sel.first sel.last");
		tkedit(e.i, e.i, sprint("%c", c), e.i+1);
		return;
	} else if(editmode == Ectlx) {
		ctlx(c);
		return;
	}
	if(keys == nil)
		keys = ref Str;
	keys.s[len keys.s] = c;
	keys.i = 0;
	keyeditorig = ref *e;

	{
		change := esc(keys, e);
		if(keys.s != ".")
			prevkeys = keys;
		if(change)
			recordundo();
		keys = nil;
	} exception ex {
	"more:*" =>
		say("key: "+ex);
	"bad:*" =>
		say("key: "+ex);
		keys = nil;
	}
}

start(x: string)
{
	if(runpid)
		raise "cannot start while command is running";
	
	if(x == nil)
		return;
	(n, err) := sh->parse(x);
	if(err == nil & n == nil)
		return;
	cmd := ref Cmd (++cmdgen, array[3] of ref Sys->FileIO, array[3] of {* => -1}, "", x, 0, "", "", nil);
	history.append(cmd);
	curcmd = history.last;

	spawn run(cmd, list of {ref Listnode (n, nil)}, err, pidc := chan of (int, string));
	p: int;
	(p, err) = <-pidc;
	if(err != nil)
		return progdone(Tstatus, x);
	runpid = p;
	tksetmode();
	cmdadd(cmd, Tcmd, x);
	edithist = nil;
	keyeditorig = ref Str ("", 0, 0, 0);
	keyeditprev = keyeditnext = nil;
}

F: adt {
	io,
	e:	ref Sys->FileIO;
	fd0,
	fd1,
	fd2:	ref Sys->FD;
};

fioerr(rc: chan of (ref F, string), s: string)
{
	rc <-= (nil, s);
}

mkfio(rc: chan of (ref F, string))
{
	sys->pctl(Sys->FORKNS, nil);
	if(sys->bind("#s", "/chan", Sys->MREPL) < 0)
		return fioerr(rc, sprint("bind: %r"));
	io := sys->file2chan("/chan", "io");
	if(io != nil)
		e := sys->file2chan("/chan", "e");
	if(io == nil || e == nil)
		return fioerr(rc, sprint("file2chan: %r"));
	fd0 := sys->open("/chan/io", Sys->OREAD);
	if(fd0 != nil)
		fd1 := sys->open("/chan/io", Sys->OWRITE);
	if(fd1 != nil)
		fd2 := sys->open("/chan/e", Sys->OWRITE);
	if(fd2 == nil)
		return fioerr(rc, sprint("open: %r"));
	rc <-= (ref F (io, e, fd0, fd1, fd2), nil);
}

fread(cmd: ref Cmd, f: ref Sys->FileIO, c: chan of (ref Cmd, (int, int, int, Sys->Rread)), pidc: chan of int)
{
	pidc <-= pid();
	for(;;)
		c <-= (cmd, <-f.read);
}

fwrite(cmd: ref Cmd, f: ref Sys->FileIO, c: chan of (ref Cmd, (int, array of byte, int, Sys->Rwrite)), pidc: chan of int)
{
	pidc <-= pid();
	for(;;)
		c <-= (cmd, <-f.write);
}

run(cmd: ref Cmd, args: list of ref sh->Listnode, sherr: string, pidc: chan of (int, string))
{
	sys->pctl(Sys->NEWPGRP|Sys->NEWFD, nil);
	xsay(sprint("run, %q", cmd.cmd));

	spawn mkfio(rc := chan of (ref F, string));
	(f, err) := <-rc;
	pidc <-= (pid(), err);
	if(err != nil)
		return;

	fpidc := chan of int;
	spawn fread(cmd, f.io, inc, fpidc);
	cmd.pids[0] = <-fpidc;
	spawn fwrite(cmd, f.io, outc, fpidc);
	cmd.pids[1] = <-fpidc;
	spawn fwrite(cmd, f.e, errc, fpidc);
	cmd.pids[2] = <-fpidc;
	cmd.f = array[] of {f.io, f.io, f.e};

	{
		if(sherr != nil)
			statusc <-= sherr;
		else {
			# we are working on a copy of shell context,
			# no problem if we are killed in nsh.run.
			# we also need a Context.copy because we did pctl NEWFD above.
			nsh := shcontext.copy(1);
			err = nsh.run(args, 0);
			shcontext = nsh;
			statusc <-= err;
		}
	} exception x {
	"fail:*" =>
		exc <-= x;
	}
	xsay("run finished");
}

respondreads(cmd: ref Cmd)
{
	if(reads.first == nil || text.first == nil) {
		tksetmode();
		return;
	}

	while(reads.first != nil && text.first != nil) {
		r := reads.takefirst();
		n := min(r.count, len text.first.e);
		d := text.first.e[:n];
		text.first.e = text.first.e[n:];
		if(len text.first.e == 0) {
			text.first = text.first.next;
			if(text.first == nil)
				text.last = nil;
		}
		r.rc <-= (d, nil);
		s: string;
		(s, inpending) = utf(inpending, d);
		cmdadd(cmd, Tin, s);
	}
	tksetmode();
}

cmdadd(cmd: ref Cmd, t: int, s: string)
{
	case t {
	Tcmd =>		cmd.cmd = s;
	Tstatus =>	cmd.status = s;
	Tex =>		cmd.ex = s;
	Texit =>	cmd.ex = s;
	}
	if(t > Tcmd)
		cmd.busy = 0;
	cmd.l = ref Rw (t, s)::cmd.l;
	if(cmd == curcmd.e)
		tkadd(t, s, 1);
}


splitmodewidgets := array[] of {
(array[] of {"in", "in", "in"},		array[] of {"in"}),
(array[] of {"in", "outerr", "outerr"},	array[] of {"in", "outerr"}),
(array[] of {"in", "outerr", "err"},	array[] of {"in", "outerr", "err"}),
};
tkadd(t: int, s: string, scroll: int)
{
	if(t == Tcmd) {
		if(!showhist)
			for(i := 0; i < len textwidgets; i++)
				tkcmd(sprint(".t.%s.t delete 1.0 end", textwidgets[i]));
		tkstatus(curcmd.e);
	} else if(t > Tcmd) {
		if(len s > 20)
			s = s[:20];
		tklabel(".s.status", s);
	}
	if(t > Tcmd && curcmd == history.last)
		tkclient->settitle(top, "run "+workdir());
	if(t >= Tcmd && !showhist)
		return;

	case t {
	Tcmd =>	s = "% "+s+"\n";
	Tstatus or
	Tex or
	Texit =>
		s = "#"+s+"\n";
	Tok =>	s = "ok"+s+"\n";
	}
	if(t >= Tcmd)
		ww := splitmodewidgets[splitmode].t1;
	else
		ww = array[] of {splitmodewidgets[splitmode].t0[t]};
	for(i := 0; i < len ww; i++) {
		w := sprint(".t.%s.t", ww[i]);
		if(scroll)
			isvisible := tkcmd(w+" dlineinfo {end -1c linestart}") != nil;
		tkcmd(w+" insert end '"+s);
		otag := tkcmd(sprint("%s tag names {end -%dc}", w, len s));
		if(otag != nil)
			tkcmd(sprint("%s tag remove %s {end -%dc} end", w, otag, len s));
		tkcmd(sprint("%s tag add %s {end -%dc} end", w, tagstrs[t], len s));
		if(scroll && isvisible)
			tkcmd(w+" see end");
	}
}

drawcmd(cmd: ref Cmd)
{
	for(l := rev(cmd.l); l != nil; l = tl l) {
		rw := hd l;
		tkadd(rw.t, rw.s, 0);
	}
}

# clear text widgets and fill those used in current splitmode
redraw()
{
	if(curcmd == nil)
		return;
	for(i := 0; i < len textwidgets; i++)
		tkcmd(sprint(".t.%s.t delete 1.0 end", textwidgets[i]));

	if(!showhist)
		drawcmd(curcmd.e);
	else
		for(l := history.first; l != nil; l = l.next)
			drawcmd(l.e);
	for(i = 0; i < len textwidgets; i++)
		tkcmd(sprint(".t.%s.t see end", textwidgets[i]));
}

# set new splitmode for in/out/err text widgets
tksplitmodeset(m: int)
{
	l := list of {"in", "outerr", "err"};
	for(; l != nil; l = tl l)
		tkcmd(sprint("pack forget .t.%s", hd l));
	case m {
	Msingle =>
		tkcmd("pack .t.in -fill both -expand 1");
	Msplit2 =>
		if(showin)
			tkcmd("pack .t.in -fill both -expand 1");
		tkcmd("pack .t.outerr -fill both -expand 1");
	Msplit3 =>
		if(showin)
			tkcmd("pack .t.in -fill both -expand 1");
		tkcmd("pack .t.outerr -fill both -expand 1");
		tkcmd("pack .t.err -fill both -expand 1");
	}
	splitmode = m;
	tksetsplitmode();
	if(splitmode == Msingle)
		tktextfocus(0);
	else if(!showin)
		tktextfocus(1);
	redraw();
}

tktextfocus(n: int)
{
	if(n > 0 && splitmode == Msingle || n > 1 && splitmode == Msplit2)
		raise "bad textfocus";
	for(i := 0; i < len textwidgets; i++)
		if(i != n)
			tkcmd(sprint(".t.%s.s configure -bg black", textwidgets[i]));
	tkcmd(sprint(".t.%s.s configure -bg #dddddd", textwidgets[n]));
	textfocus = n;
}

tkcompletehide()
{
	if(!showcomplete)
		return;
	tkcmd("pack .t -before .c -fill both -expand 1");
	tkcmd("pack forget .c");
	tkcmd(".c.complete delete 1.0 end");
	showcomplete = 0;
}

tkcompleteshow()
{
	if(showcomplete)
		return;
	tkcmd("pack .c -before .t -fill both -expand 1");
	tkcmd("pack forget .t");
	showcomplete = 1;
}

tkstatus(cmd: ref Cmd)
{
	tklabel(".s.gen", sprint("%5d", cmd.gen));
	f0 := f1 := f2 := "";
	if(cmd.f[0] != nil) f0 = "0";
	if(cmd.f[1] != nil) f1 = "1";
	if(cmd.f[2] != nil) f2 = "2";
	tklabel(".s.f0", f0);
	tklabel(".s.f1", f1);
	tklabel(".s.f2", f2);
	if(cmd == history.last.e)
		st := string runpid;
	else
		st = cmd.status+cmd.ex; # only one is non-nil
	tklabel(".s.status", st);
	tklabel(".s.cmd", cmd.cmd);
}

tkeditstr(): ref Str
{
	e := tkcmd(".e.edit get");
	i := int tkcmd(".e.edit index insert");
	return ref Str (e, i, i, i);
}

# replace s-e with ns, leaving cursor at ins
tkedit(s, e: int, ns: string, ins: int): string
{
	r := tkcmd(sprint(".e.edit get %d %d", s, e));
	tkcmd(sprint(".e.edit delete %d %d; .e.edit insert %d '%s", s, e, s, ns));
	tkcmd(sprint(".e.edit icursor %d; .e.edit see insert", ins));
	return r;
}

tksetshowhist()		{ tkset(".s.showhist", showhist, " h"); }
tksetshowin()		{ tkset(".s.showin", showin, " i"); }
tkseteditmode()		{ tkset(".s.editmode", editmode, "[ x"); }
tksetshowcolors()	{ tkset(".s.showcolors", showcolors, " c"); }
tksetsplitmode()	{ tkset(".s.splitmode", splitmode, "123"); }

tkset(w: string, v: int, opts: string)
{
	if(v < 0 || v >= len opts)
		v = len opts-1;
	tklabel(w, opts[v:v+1]);
}

tklabel(w: string, v: string)
{
	tkcmd(w+" configure -text '"+v);
}

tksetmode()
{
	c := "#dddddd";
	if(runpid) {
		c = "green";
		if(reads.first != nil)
			c = "blue";
		else if(text.first != nil)
			c = "red";
	}
	tkcmd(".e.mode configure -bg "+c);
}

tktextwidth(): int
{
	w := ".t.outerr.t";
	if(splitmode == Msingle)
		w = ".t.in.t";
	width := int tkcmd(w+" cget -actwidth");
	charwidth := int tkcmd(".e.mode cget -actwidth");
	return width/charwidth;
}

tktextsel(): string
{
	w := sprint(".t.%s.t", textwidgets[textfocus]);
	ranges := tkcmd(w+ " tag ranges sel");
	if(ranges == nil)
		ranges = "1.0 end";
	return tkcmd(w+ " get "+ranges);
}

tkup()
{
	tkcmd("update");
}

tkcmd(s: string): string
{
	r := tk->cmd(top, s);
	if(r != nil && r[0] == '!' && dflag)
		warn(sprint("tkcmd: %q: %s", s, r));
	if(dflag > 1)
		say(sprint("tk: %s -> %s", s, r));
	return r;
}

isabs(s: string): int
{
	return str->prefix("/", s) || str->prefix("#", s);
}

tkcmds(a: array of string)
{
	for(i := 0; i < len a; i++)
		tkcmd(a[i]);
}

xwarn(s: string)
{
	warnc <-= s;
}

xsay(s: string)
{
	if(dflag)
		xwarn(s);
}

pid(): int
{
	return sys->pctl(0, nil);
}

min(a, b: int): int
{
	if(a < b)
		return a;
	return b;
}

max(a, b: int): int
{
	if(a > b)
		return a;
	return b;
}

progctl(pid: int, s: string)
{
	sys->fprint(sys->open(sprint("/prog/%d/ctl", pid), Sys->OWRITE), "%s", s);
}

kill(pid: int)
{
	progctl(pid, "kill");
}

killgrp(pid: int)
{
	progctl(pid, "killgrp");
}

rev[T](l: list of T): list of T
{
	r: list of T;
	for(; l != nil; l = tl l)
		r = hd l::r;
	return r;
}

say(s: string)
{
	if(dflag)
		warn(s);
}

quit()
{
	killgrp(pid());
	exit;
}

workdir(): string
{
	return sys->fd2path(sys->open(".", Sys->OREAD));
}

warn(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
}

fail(s: string)
{
	warn(s);
	killgrp(pid());
	raise "fail:"+s;
}
