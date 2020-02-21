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