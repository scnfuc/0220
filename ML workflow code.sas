/* Identify: Create a Format  */
proc format  casfmtlib="chicagofmts" sessref=casauto;
    value $fbi 
    '01A' = 'Homicide 1st & 2nd Degree'
    '02' = 'Criminal Sexual Assault'
    '03' = 'Robbery'
    '04A' = 'Aggravated Assault'
    '04B' = 'Aggravated Battery'
    '05' = 'Burglary'
    '06' = 'Larceny'
    '07' = 'Motor Vehicle Theft'
    '08A' = 'Simple Assault'
    '08B' = 'Simple Battery'
    '09' = 'Arson'
    '10' = 'Forgery & Counterfeiting'
    '11' = 'Fraud'
    '12' = 'Embezzlement'
    '13' = 'Stolen Property'
    '14' = 'Vandalism'
    '15' = 'Weapons Violation'
    '16' = 'Prostitution'
    '17' = 'Criminal Sexual Abuse'
    '18' = 'Drug Abuse'
    '19' = 'Gambling'
    '20' = 'Offenses Against Family'
    '22' = 'Liquor License'
    '24' = 'Disorderly Conduct'
    '26' = 'Misc Non-Index Offense'
;

run;
/*Identify: Merge the dataset  */
libname mycas cas sessref=casauto;

data mycas.crimeCensus/ sessref=casauto;
   merge mycas.crime(in=in1) mycas.census(in=in2);
   by community_area;
   if in1;
run;

proc casutil;
   contents casdata="crimeCensus";
quit;

/*Explore: Bar Chart  */
 

/*--Set output size--*/
ods graphics / reset imagemap;

/*--SGPLOT proc statement--*/
proc sgplot data=MYCAS.CRIMECENSUS;
	/*--TITLE and FOOTNOTE--*/
	title "Types of Crimes and Arrest Rates";

	/*--Bar chart settings--*/
	vbar fbi_code / categoryorder=respdesc group=Arrest groupdisplay=Stack name='Bar';

	/*--Category Axis--*/
	xaxis display=(nolabel);

	/*--Response Axis--*/
	yaxis;
run;

ods graphics / reset;
title; 


/* Prepare: Partitioning */
ods noproctitle;

proc partition data=MYCAS.CRIMECENSUS partind samppct=30 samppct2=10 seed=9878;
	by Arrest;
	output out=MYCAS.cwpart;
run;

/*Prepare: Explore the Cardinality  */
ods noproctitle;

proc cardinality data=MYCAS.CWPART outcard=mycas.card out=MYCAS.levelDetailTemp;
run;

proc print data=mycas.card label;
	var _varname_ _fmtwidth_ _type_ _rlevel_ _more_ _cardinality_ _nmiss_ _min_ 
		_max_ _mean_ _stddev_;
	title 'Variable Summary';
run;

proc print data=MYCAS.levelDetailTemp (obs=20) label;
	title 'Level Details';
run;

proc delete data=MYCAS.levelDetailTemp;
run;

/*Model: Build a decision tree  */
ods noproctitle;

proc treesplit data=MYCAS.CWPART;
	partition role=_PartInd_ (validate='1' train='0');
	input per_capita_income hardship_index percent_aged_under_18_or_over_64 
		percent_of_housing_crowded percent_aged_25_without_high_sch 
		percent_aged_16_unemployed percent_households_below_poverty / level=interval;
	input fbi_code Location_Description Domestic Beat District Ward Community_Area 
		/ level=nominal;
	target arrest_code / level=nominal;
	grow igr;
	prune none;
	score out=mycas.ap_scored_treesplit copyvars=(_PartInd_ arrest_code);
	code file="/r/ge.unx.sas.com/vol/vol120/u12/scnfuc/score.sas";
run;

/*Assess: Assess tree split  */
ods noproctitle;

proc assess data=MYCAS.AP_SCORED_TREESPLIT nbins=10 ncuts=10;
	target arrest_code / event="1" level=nominal;
	input P_arrest_code1;
	fitstat pvar=P_arrest_code0 / pevent="0" delimiter=",";
	ods output ROCInfo=WORK._roc_temp LIFTInfo=WORK._lift_temp;
run;

data _null_;
	set WORK._roc_temp(obs=1);
	call symput('AUC', round(C, 0.01));
run;

proc sgplot data=WORK._roc_temp noautolegend aspect=1;
	title 'ROC Curve (Target = arrest_code, Event = 1)';
	xaxis label='False positive rate' values=(0 to 1 by 0.1);
	yaxis label='True positive rate' values=(0 to 1 by 0.1);
	lineparm x=0 y=0 slope=1 / transparency=.7 LINEATTRS=(Pattern=34);
	series x=fpr y=sensitivity;
	inset "AUC=&AUC"/position=bottomright border;
run;

proc sgplot data=WORK._lift_temp noautolegend;
	title 'Lift Chart (Target = arrest_code, Event = 1)';
	xaxis label='Population Percentage';
	yaxis label='Lift';
	series x=depth y=lift;
run;

proc delete data=WORK._lift_temp WORK._roc_temp;
run;

/* Score: Download and prepare latest data */



/* This option enables Server Name Indication on UNIX */
options set=SSL_USE_SNI=1;

/* Retrieve the columns that are used in the model only.    */
/* Retrieve data with a date after 15FEB16                  */
filename chicago url 'https://data.cityofchicago.org/resource/6zsd-86xi.json?$query=
select%20id%2C%20case_number%2C%20date%2C%20community_area
%2C%20fbi_code%2C%20location_description%20%2Cdomestic%20%2Cbeat
%20%2Cdistrict%20%2Cward%20%2Carrest
%20where%20date%20%3E%20%272016-02-15%27';
libname chicago sasejson;

data mycas.arrest err;
  set chicago.root(rename=(
      date=tmpts arrest=arrest_code domestic=tmpds 
      beat=tbeat community_area=tca district=tdis   id=tid 
      ward=tward
      ));

  if arrest_code eq 0 then arrest = 'false';
  else arrest = 'true';
  if tmpds eq 0 then domestic = 'false';
  else domestic = 'true';

  beat           = input(tbeat, best12.);
  community_area = input(tca,   best12.);
  district       = input(tdis,  best12.);
  id             = input(tid,   best12.);
  ward           = input(tward, best12.);
 
  format fbi_code $fbi. location_description $47.
         arrest domestic $5.
         arrest_code 8. date mmddyy10. timestamp datetime. ;

  pos = kindex(tmpts, 'T');
  if -1 eq pos then output err;
  date = input(substr(tmpts,1,pos-1), yymmdd10.);
  time = input(substr(tmpts,pos+1), time.);
  timestamp = dhms(date,0,0,time);

  drop tmpts pos time tmpds tbeat tca tdis tid tward;
  output mycas.arrest;
run;

data mycas.latest_crimes;
    merge 
       mycas.arrest(in=in1)  
       mycas.census(in=in2);
    by community_area;
    if in1;
run;

/*Score: Score new data  */
ods noproctitle;

data mycas.latest_Treesplit;
	set MYCAS.LATEST_CRIMES;
	%include '/r/ge.unx.sas.com/vol/vol120/u12/scnfuc/score.sas';
run;

proc contents data=mycas.latest_Treesplit;
run;
