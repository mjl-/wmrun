Link: adt[T] {
	prev, next:	cyclic ref Link;
	e:	T;
};

List: adt[T] {
	first,
	last:	ref Link[T];

	new:	fn(): ref List;
	append:	fn(l: self ref List, e: T);
	takefirst:	fn(l: self ref List): T;
};

List[T].new(): ref List
{
	return ref List[T] (nil, nil);
}

List[T].append(l: self ref List, e: T)
{
	if(l.first == nil) {
		l.first = l.last = ref Link[T] (nil, nil, e);
	} else {
		l.last.next = ref Link[T] (l.last, nil, e);
		l.last = l.last.next;
	}
}

List[T].takefirst(l: self ref List): T
{
	e := l.first.e;
	if(l.first == l.last)
		l.first = l.last = nil;
	else {
		l.first = l.first.next;
		l.first.prev = nil;
	}
	return e;
}
