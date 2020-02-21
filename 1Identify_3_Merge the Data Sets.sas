libname mycas cas sessref=casauto;

data mycas.crimeCensus/ sessref=casauto;
   merge mycas.crime(in=in1) mycas.census(in=in2);
   by community_area;
   if in1;
run;

proc casutil;
   contents casdata="crimeCensus";
quit;