# no quoting yet
complete(s: string, si, ei: int)
{
	w := s[si:ei];
	dir := names->dirname(w);
	file := names->basename(w, nil);
	say(sprint("completing in dir %q, for file prefix %q", dir, file));

	l := filematches(dir, file);
	if(dir != nil && dir[len dir-1] != '/')
		dir[len dir] = '/';
	if(l == nil)
		r := w;
	else if(len l == 1) {
		r = dir+hd l;
		tkcompletehide();
	} else {
		pre := hd l;
		hits := pre+"\n";
		for(l = tl l; l != nil; l = tl l) {
			mm := hd l;
			hits += mm+"\n";
			for(i := 0; i < len pre && i < len mm && pre[i] == mm[i]; i++)
				{}
			pre = pre[:i];
		}
		r = dir+pre;
		tkcmd(".c.complete delete 1.0 end");
		tkcmd(".c.complete insert 1.0 '"+mc(hits));
		tkcompleteshow();
	}
	tkedit(si, ei, r, si+len r);
}

mc(s: string): string
{
	p0 := sys->pipe(fd0 := array[2] of ref Sys->FD);
	p1 := sys->pipe(fd1 := array[2] of ref Sys->FD);
	if(p0 < 0 || p1 < 0) {
		warn(sprint("pipe: %r"));
		return s;
	}

	pidc := chan[2] of int;
	spawn mcinit(list of {"mc", "-c", string tktextwidth()}, fd0[0], fd1[0], pidc);
	spawn mcwrite(fd0[1], s, pidc);
	fdx := fd1[1];
	fd0 = fd1 = nil;

	b := bufio->fopen(fdx, bufio->OREAD);
	r: string;
more:
	for(;;)
	case c := b.getc() {
	bufio->EOF =>
		break more;
	bufio->ERROR =>
		warn(sprint("read: %r"));
		r = s;
		break more;
	* =>
		r[len r] = c;
	}
	kill(<-pidc);
	kill(<-pidc);
	return r;
}

mcinit(args: list of string, fd0, fd1: ref Sys->FD, pidc: chan of int)
{
	pidc <-= pid();
	sys->pctl(sys->NEWFD, list of {fd0.fd, fd1.fd, 2});
	sys->dup(fd0.fd, 0);
	sys->dup(fd1.fd, 1);
	m := load Shcmd "/dis/mc.dis";
	m->init(drawcontext, args);
}

mcwrite(fd: ref Sys->FD, s: string, pidc: chan of int)
{
	pidc <-= pid();
	sys->pctl(sys->NEWFD, list of {fd.fd, 2});
	if(sys->write(fd, d := array of byte s, len d) != len d)
		warn(sprint("mc write: %r"));
}

filematches(p, f: string): list of string
{
	if(p == nil)
		p = ".";
	(a, n) := readdir->init(p, Readdir->NAME|Readdir->DESCENDING);
	if(n < 0)
		return nil;
	l: list of string;
	for(i := 0; i < len a; i++)
		if(str->prefix(f, a[i].name)) {
			s := a[i].name;
			if(a[i].mode & Sys->DMDIR)
				s += "/";
			l = s::l;
		}
	return l;
}
