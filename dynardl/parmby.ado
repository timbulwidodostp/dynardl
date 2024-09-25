#delim ;
prog def parmby,rclass;
version 8.0;
*
 Call a regression command followed by -parmest- with by-variables,
 creating an output data set containing the by-variables
 together with the parameter sequence number -parmseq-
 and all the variables in a -parmest- output data set.
*! Author: Roger Newson
*! Date: 22 July 2003    (SJ3-3: st0043)
*;


gettoken cmd 0: 0;
if `"`cmd'"' == `""' {;error 198;};

syntax [ ,BY(varlist) COMmand LIst(string asis) SAving(string asis) noREstore FAST FList(string) REName(string) FOrmat(string) * ];
*
 -by- is list of by-variables.
 -command- specifies that the regression command is saved in the output data set
  as a string variable named -command-.
 Other options are as defined for -parmest-.
*;

*
 Set restore to norestore if fast is present
 and check that the user has specified one of the four options:
 list and/or saving and/or norestore and/or fast.
*;
if "`fast'"!="" {;
    local restore="norestore";
};
if (`"`list'"'=="")&(`"`saving'"'=="")&("`restore'"!="norestore")&("`fast'"=="") {;
    disp as error "You must specify at least one of the four options:"
      _n "list(), saving(), norestore, and fast."
      _n "If you specify list(), then the output variables specified are listed."
      _n "If you specify saving(), then the new data set is output to a disk file."
      _n "If you specify norestore and/or fast, then the new data set is created in the memory,"
      _n "and any existing data set in the memory is destroyed."
      _n "For more details, see {help parmest:on-line help for parmby and parmest}.";
    error 498;
};


*
 Preserve old data set if restore is set or fast unset
*;
if("`fast'"==""){;
    preserve;
};

* Echo the command and by-variables *;
disp in green "Command: " in yellow `"`cmd'"';
if "`by'"!="" {;disp in green "By variables: " in yellow "`by'";};

*
 Define by-group sequence number variable in -group-
*;
tempvar group first seqnum;
qui gene long `seqnum'=_n;
qui compress `seqnum';
if "`by'"=="" {;
  sort `seqnum';
  qui gene byte `group'=1;
};
else {;
  sort `by' `seqnum';
  qui by `by':gene byte `first'=_n==1;
  qui gene long `group'=sum(`first');
  qui compress `group';
  drop `first';
};
qui summ `group';local ngroup=r(max);

*
 Save to file -tf0- if by-variables are present
*;
if "`by'"!="" {;
  tempfile tf0;
  bysave `group' "`by'" `"`tf0'"';
};

*
 Execute command once per by-group
 building a list of by-groups where estimation was successful
 in local macro -bglist-
*;
local i1=0;local bglist "";
while `i1'<`ngroup' {;local i1=`i1'+1;
  tempfile tf`i1';
  cap noi cmdexe `group' `i1' `"`by'"' `"`cmd'"' `"`options'"' `"`tf`i1''"';
  if _rc==0 {;
    local bglist "`bglist' `i1'";
  };
};

* Concatenate output data sets *;
local ngsucc:word count `bglist';
if `ngsucc'==0 {;
  disp in red "Command was not completed successfully for any group";
  error 498;
};
local i2:word 1 of `bglist';
use `"`tf`i2''"',clear;
local i1=1;
while `i1'<`ngsucc' {;local i1=`i1'+1;
  local i2:word `i1' of `bglist';
  qui append using `"`tf`i2''"';
};

* Add variable -command- if requested *;
if "`command'"!="" {;
  qui gene str1 command="";
  qui replace command=`"`cmd'"';
  order command;
  lab var command "Estimation command";
};

*
 Rename variables if requested
 (including -parmseq- and -command-, which cannot be renamed by -parmest-)
 and create macros -parmseq- and -commandv-,
 containing -parmseq- and -command- variable names
*;
local parmseq "parmseq";
if "`command'"=="" {;local commandv "";};
else {;local commandv "command";};
if "`rename'"!="" {;
    local nrename:word count `rename';
    if mod(`nrename',2) {;
        disp in green 
          "Warning: odd number of variable names in rename list - last one ignored";
        local nrename=`nrename'-1;
    };
    local nrenp=`nrename'/2;
    local i1=0;
    while `i1'<`nrenp' {;
        local i1=`i1'+1;
        local i3=`i1'+`i1';
        local i2=`i3'-1;
        local oldname:word `i2' of `rename';
        local newname:word `i3' of `rename';
        cap{;
            confirm var `oldname';
            confirm new var `newname';
        };
        if _rc!=0 {;
            disp in green
             "Warning: it is not possible to rename `oldname' to `newname'";
        };
        else {;
            rename `oldname' `newname';
            if "`oldname'"=="parmseq" {;local parmseq "`newname'";};
            if "`oldname'"=="command" {;local commandv "`newname'";};
        };
    };
};

*
 Format variables if requested
*;
if `"`format'"'!="" {;
    local vlcur "";
    foreach X in `format' {;
        if index(`"`X'"',"%")!=1 {;
            * varlist item *;
            local vlcur `"`vlcur' `X'"';
        };
        else {;
            * Format item *;
            unab Y : `vlcur';
            conf var `Y';
            cap format `Y' `X';
            local vlcur "";
        };
    };
};

* Add by-variables from file -tf0- if present *;
if "`by'"!="" {;
  sort `group' `parmseq';
  tempvar merg;
  qui merge `group' using `"`tf0'"',_merge(`merg');
  qui keep if `merg'==3;
  drop `merg';
};

*
 Drop temporary variables
 and order and sort output data set
*;
drop `group';
order `by' `parmseq' `commandv';sort `by' `parmseq';

*
 List variables if requested
*;
if `"`list'"'!="" {;
    if "`by'"=="" {;
        disp _n as text "Listing of results:";
        list `list';
    };
    else {;
        disp _n as text "Listing of results by: " as result "`by'";
        by `by':list `list';
    };
};

*
 Save data set if requested
*;
if(`"`saving'"'!=""){;
    capture noisily save `saving';
    if(_rc!=0){;
        disp in red `"saving(`saving') invalid"';
        exit 498;
    };
    tokenize `"`saving'"',parse(" ,");
    local fname `"`1'"';
    if(index(`"`fname'"'," ")>0){;
        local fname `""`fname'""';
    };
    * Add filename to file list in FList if requested *;
    if(`"`flist'"'!=""){;
        if(`"$`flist'"'==""){;
            global `flist' `"`fname'"';
        };
        else{;
            global `flist' `"$`flist' `fname'"';
        };
    };
};

*
 Restore old data set if restore is set
 or if program fails when fast is unset
*;
if "`fast'"=="" {;
    if "`restore'"=="norestore" {;
        restore,not;
    };
    else {;
        restore;
    };
};

* Return results *;
return local by "`by'";
return local command `"`cmd'"';

end;

prog def bysave;
version 7.0;
args group by tf;
*
 Save a file with 1 obs per by-group
 and data on by-group sequence number
 and by-variables.
 -group- is a variable indicating by-group.
 -by- is a list of by-variables (by which data are sorted).
 -tf- is a temporary output file to be saved.
*;

preserve;
qui by `by':keep if _n==1;
keep `group' `by';
sort `group';
qui save `"`tf'"',replace;
restore;

end;

prog def cmdexe;
version 8.0;
args group gpcur by cmd parmopt tf;
*
 Execute a command for the current by-group.
 -group- is a variable containing sequence number of by-group.
 -gpcur- is sequence number of the current by-group.
 -by- is list of by-variables (by which data are sorted if present).
 -cmd- is the command to be executed.
 -parmopt- is options to be passed through to -parmest-.
 -tf- is the name of a temporary file to be saved.
*;

preserve;
qui keep if `group'==`gpcur';
if `"`by'"'!="" {;
  by `by':list if 0,nohe;
};
`cmd';
parmest,`parmopt' fast;
qui gene long `group'=`gpcur';
qui gene long parmseq=_n;
qui compress `group' parmseq;
lab var parmseq "Parameter sequence number";
qui save `"`tf'"',replace;
restore;

end;
