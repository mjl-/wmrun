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
		r := dir;
	else if(len l == 1)
		r = dir+hd l;
	else {
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
		if(file == pre) {
			tkcmd(".c.complete delete 1.0 end");
			tkcmd(".c.complete insert 1.0 '"+hits);
			tkcompleteshow();
		}
	}
	tkedit(si, ei, r, si+len r);
}

filematches(p, f: string): list of string
{
	if(p == nil)
		p = ".";
	(a, n) := readdir->init(p, Readdir->NAME);
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
