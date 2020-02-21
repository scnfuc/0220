proc casutil;
    load data=Demo.census;
    load data=Demo.crime;

    contents casdata="crime";
    contents casdata="census";
quit;