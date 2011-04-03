Str: adt {
	s:	string;
	i:	int;
	si,
	ei:	int;  # for motion commands, start and end for motion (ordered)

	more:		fn(x: self ref Str): int;
	char:		fn(x: self ref Str): int;
	xget:		fn(x: self ref Str): int;
	in:		fn(x: self ref Str, cl: string): int;
	readrep:	fn(x: self ref Str, def: int): (int, string);
	previn:		fn(x: self ref Str, cl: string): int;
	skipcl:		fn(x: self ref Str, cl: string): int;
	rskipcl:	fn(x: self ref Str, cl: string): int;
	findcl:		fn(x: self ref Str, cl: string): int;
	rfindcl:	fn(x: self ref Str, cl: string): int;
	text:		fn(x: self ref Str): string;
};

Str.more(x: self ref Str): int
{
	return x.i < len x.s;
}

Str.char(x: self ref Str): int
{
	if(!x.more())
		return -1;
	return x.s[x.i];
}

Str.xget(x: self ref Str): int
{
	if(!x.more())
		raise "more:";
	return x.s[x.i++];
}

Str.in(x: self ref Str, cl: string): int
{
	return x.more() && str->in(x.char(), cl);
}

Str.readrep(x: self ref Str, def: int): (int, string)
{
	if(!x.in("1-9"))
		return (def, "");
	s: string;
	s[len s] = x.xget();
	while(x.in("0-9"))
		s[len s] = x.xget();
	return (int s, s);
}

Str.previn(x: self ref Str, cl: string): int
{
	if(x.i <= 0)
		return 0;
	return str->in(x.s[x.i-1], cl);
}

Str.skipcl(x: self ref Str, cl: string): int
{
	while(x.in(cl))
		x.i++;
	return x.i;
}

Str.rskipcl(x: self ref Str, cl: string): int
{
	while(x.previn(cl))
		x.i--;
	return x.i;
}

Str.findcl(x: self ref Str, cl: string): int
{
	while(x.char() >= 0 && !x.in(cl))
		x.i++;
	return x.in(cl);
}

Str.rfindcl(x: self ref Str, cl: string): int
{
	while(x.i > 0 && !x.previn(cl))
		x.i--;
	return x.in(cl);
}

Str.text(x: self ref Str): string
{
	return sprint("Str(s %q, i %d, si %d, ei %d)", x.s, x.i, x.si, x.ei);
}


esc(k: ref Str, e: ref Str): int
{
	change := 1;
	k.i = 0;
	say(sprint("esc, k %s, e %s", k.text(), e.text()));
	(rep1, rep1str) := k.readrep(1);
	case x := k.xget() {
	#R
	#~
	# '/' '?' 'n' 'N'
	'i' or
	'I' or
	'a' or
	'A' or
	's' or
	'S' or
	'C' =>
		# repeat for insertions is not supported
		editmode = Einsert;
		tklabel(".s.editmode", "");
		case x {
		'I' =>	move("^", e);
		'a' =>	move("l", e);
		'A' =>	move("$", e);
		's' =>	editbuf = tkedit(e.i, e.i+rep1, "", e.i);
		'S' =>	editbuf = tkedit(0, len e.s, "", 0);
		'C' =>	editbuf = tkedit(e.i, len e.s, "", e.i);
		}
		change = 0;
	'c' =>
		editmode = Einsert;
		tklabel(".s.editmode", "");
		if(motion(k, e, rep1, 'c'))
			editbuf = tkedit(e.si, e.ei, "", e.si);
		else {
			move("^", e);
			editbuf = tkedit(e.i, len e.s, "", e.i);
		}
		change = 0;
	'r' =>
		y := k.xget();
		if(y == '\n')
			raise "bad:'r' got newline";
		n := min(rep1, len e.s-e.i);
		s: string;
		for(i := 0; i < n; i++)
			s[len s] = y;
		editbuf = tkedit(e.i, e.i+n, s, e.i+n);
	'y' =>
		if(motion(k, e, rep1, 'y'))
			editbuf = e.s[e.si:e.ei];
		else
			editbuf = e.s;
	'Y' =>
		editbuf = e.s[e.i:];
	'p' =>
		while(rep1--) {
			tkedit(e.i, e.i, editbuf, e.i);
			e = tkeditstr();
		}
	'P' =>
		while(rep1--) {
			tkedit(e.i, e.i, editbuf, e.i+len editbuf);
			e = tkeditstr();
		}
	'.' =>
		# for simpler implementation, only commands can be repeated, not insertions
		if(prevkeys != nil)
			while(rep1--) {
				change = esc(prevkeys, e);
				e = tkeditstr();
			}
	'u' =>
		while(rep1-- && keyeditprev != nil) {
			keyeditnext = e::keyeditnext;
			ee := hd keyeditprev;
			keyeditprev = tl keyeditprev;
			tkedit(0, len e.s, ee.s, ee.i);
			e = ee;
		}
		change = 0;
	'r'-16r60 => # ^r
		while(rep1-- && keyeditnext != nil) {
			keyeditprev = e::keyeditprev;
			ee := hd keyeditnext;
			keyeditnext = tl keyeditnext;
			tkedit(0, len e.s, ee.s, ee.i);
			e = ee;
		}
		change = 0;
	'j' =>
		while(rep1--) {
			if(!histnext(e))
				break;
			if(rep1)
				e = tkeditstr();
		}
		change = 1;
	'k' =>
		while(rep1--) {
			if(!histprev(e))
				break;
			if(rep1)
				e = tkeditstr();
		}
		change = 1;
	'g' or
	'G' =>
		if(x == 'g')
			case k.xget() {
			'g' =>	{} # handled below
			* =>	raise "bad:bad 'g'";
			}

		n: ref Link[ref Cmd];
		if(rep1str == nil) {
			if(x == 'g')
				n = history.first;
			else
				n = history.last;
		} else {
			for(l := history.first; l != nil && l.e.gen != rep1; l = l.next)
				{}
			n = l;
		}
		if(n != nil) {
			edithist = n;
			tkedit(0, len e.s, n.e.cmd, 0);
		}
		change = 0;
	'D' =>
		editbuf = tkedit(e.i, len e.s, "", e.i);
	'd' =>
		if(motion(k, e, rep1, 'd'))
			editbuf = tkedit(e.si, e.ei, "", e.si);
		else
			editbuf = tkedit(0, len e.s, "", 0);
	'x' =>
		editbuf = tkedit(e.i, min(len e.s, e.i+rep1), "", e.i);
	'X' =>
		i := max(0, e.i-rep1);
		editbuf = tkedit(i, e.i, "", i);
	* =>
		k.i = 0;
		motion(k, e, 1, 0);
		tkedit(0, 0, "", e.i);
		change = 0;
	}
	if(k.more())
		raise "remaining chars in keys";
	return change;
}

Nonword: con "\u0001-\u0008\u000b-\u001f!-/:-@[-`{-\u007f";  # without whitespace
Word: con "^\u0001-/:-@[-`{-\u007f";  # without whitespace
Whitespace: con " \t\n";
Nonwhitespace := "^"+Whitespace;

movexword(e: ref Str)
{
	if(e.in(Word))
		e.skipcl(Word);
	else if(e.in(Nonword))
		e.skipcl(Nonword);
}

rmovexword(e: ref Str)
{
	if(e.in(Word))
		e.rskipcl(Word);
	else
		e.rskipcl(Nonword);
}

move(s: string, e: ref Str)
{
	k := ref Str (s, 0, 0, 0);
	motion(k, e, 1, 0);
	tkedit(0, 0, "", e.i);
}

motion(k: ref Str, e: ref Str, rep1, cmdchar: int): int
{
	say(sprint("motion, k %s, e %s, rep1 %d", k.text(), e.text(), rep1));
	(rep2, nil) := k.readrep(1);
	rep := rep1*rep2;

	case x := k.xget() {
	'^' =>	e.i = 0; e.findcl(Nonwhitespace);
	'0' =>	e.i = 0;
	'$' =>	e.i = len e.s;
	'w' =>
		while(rep--) {
			movexword(e);
			e.skipcl(Whitespace);
		}
	'W' =>
		while(rep--) {
			e.skipcl(Nonwhitespace);
			e.skipcl(Whitespace);
		}
	'e' =>
		while(rep--) {
			e.skipcl(Whitespace);
			movexword(e);
		}
	'E' =>
		while(rep--) {
			e.skipcl(Whitespace);
			e.skipcl(Nonwhitespace);
		}
	'b' =>
		while(rep--) {
			e.rskipcl(Whitespace);
			if(e.i > 0)
				e.i--;
			rmovexword(e);
		}
	'B' =>
		while(rep--) {
			e.rskipcl(Whitespace);
			e.rskipcl(Nonwhitespace);
		}
	kb->APP|'h' or
	'h' =>	e.i = max(0, e.i-rep);
	' ' or
	'l'=>	e.i = min(len e.s, e.i+rep);
	'|' =>	e.i = max(len e.s, rep);
	'%' =>
		pat: con "[{(]})";
		orig := e.i;
		if(!e.findcl(pat) && !e.rfindcl(pat)) {
			e.i = orig;
			xwarn("char not found");
			break;
		}
		c := e.char();
		for(i := 0; i < len pat && pat[i] != c; i++)
			{}
		oc := pat[(i+3)%6];
		delta := 1;
		if(i > 2)
			delta = -1;
		e.i += delta;
		n := 1;
		while(e.i >= 0 && e.i < len e.s) {
			y := e.char();
			if(y < 0)
				break;
			else if(y == c)
				n++;
			else if(y == oc)
				n--;
			if(n == 0)
				break;
			e.i += delta;
		}
		if(n != 0)
			e.i = orig;
	* =>
		if(cmdchar == x)
			return 0;
		raise "bad:not a motion command";
	}
	e.ei = e.i;
	if(e.si > e.ei)
		(e.si, e.ei) = (e.ei, e.si);
	return 1;
}
