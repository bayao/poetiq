\e 1
reset:{i::0; n::count order;}

eof:{i>=n}

curtime::exec first time from order where i=get`i

/ determines the order in which the data should be replayed
orderdata:{[tbls]update countdown:((1 _deltas time),0Wp) from `time xasc (,/){![?[x;();0b;enlist[`time]!enlist(+;`time;`date)];();0b;`tbl`row!(enlist x;`i)]}each tbls}

/ loads data from the hdb
loaddata:{[tbls;bgn;end;syms]
	.lg.o[`backtest;"loading data"];
	h:.servers.gethandlebytype[`gateway;`any];
	neg[h](`.gw.asyncexec;(`events;tbls;bgn;end;syms);`hdb); r:h[]; / deferred async
	$[99h~type r;(@[`.;;:;]').(key;value)@\:r;.lg.e[`backtest;r]]; / set data
	order::orderdata tbls; loaded::1b;
	.lg.o[`backtest;"data loaded"];
 };

/ get the ith event
event:{{[t;x](t;value exec from t where i=x)}. value first each exec tbl,row from order where i=x};

/feed:{h`.u.upd,x;i+::1;};

feed:{[x;countdown]
	while[ p|(.z.p < deadline & p:hswitch "pause")];
	deadline::countdown+tsent::.z.p; h`.u.upd,x;i+::1; hswitch "pause:1b";};

setscope:{
	s:k!"SPPS"$x k:`tbls`bgn`end`syms;
	scope::@[s;`bgn`end;:;first each s`bgn`end];
 };

init:{loaddata . value scope;reset[];};

/ use the discovery service to find the tickerplant to publish data to
.servers.startup[]
h:.servers.gethandlebytype[`bttickerplant;`any]
hswitch:.servers.gethandlebytype[`btswitch;`any]
deadline:.z.p; 
setscope .proc.params
init 0

/ ticks are preloaded (slightly faster)
run:{
	reset[];
	.lg.o[`backtest;"feeding events"];
	/feed each {[x;y](x;value exec from x where i=y)}.'flip value exec tbl,row from order;
	feed .' {[x;y;z] ((x;value exec from x where i=y); z)}.'flip value exec tbl,row,countdown from order;
	h(`.u.end;`);
	.lg.o[`backtest;"events fed"];
 };

if[not `wait in key .proc.params;run[]]


\
scope
trade
quote
order