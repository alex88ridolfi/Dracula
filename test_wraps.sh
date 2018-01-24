#!/bin/sh


##### (1) 

# Edit these values to match last iteration of sieve.sh. In this case, the nex-label of sieve.sh is ''J''.
# Here ``J'' is added to ``previous labels''.
# Finally, please add a label called PHASE1 to your TOA list, in any position.

prev_labels="0 A B C D E F G H I J"
next_label="1"

##### (2) Entries that only need to be set at the beginning

# specify version of TEMPO we're using
# path to $TEMPO directory, which contains tempo.cfg, obsys.dat, etc.
TEMPO=
# path to tempo executable
alias tempo=

# specify where we are--this is the directory where we want to write our results
basedir=$PWD

# specify the files we are going to work with
# (.par and .tim file names--these files should be in your basedir)
# Example files given in this repository.

ephem=47Tucaa.par
fitephem=J0024-7205AA.par
timfile=TOA.tim

#make a new .tim file without any PHASE statements AND without any JUMP statements
   
cat $timfile | grep -v PHASE | grep -v JUMP > trial2.tim

##### YOU SHOULD NOT NEED TO EDIT BEYOND THIS LINE

# remove previous WRAPs file

start=`date`

# How many acceptable solutions we have from previous wrapper output

n=`wc acc_WRAPs.dat | awk '{print $1}'`
n=`expr $n + 1`

# set the counter that will go through these solutions
m=1

while [ "$m" -lt "$n" ]  # this is the outer loop, where we cycle through the acceptable solutions
do
   # ********** CHECK variable names and positions
   acc_combination=""
   edtim1_str="cat "$timfile" | "

   col=1
   for label in $prev_labels
   do
      this_label=`head -$m acc_WRAPs.dat | tail -1 | awk -v cvar="$col" '{print $cvar}'`
      acc_combination="$acc_combination"$this_label" "
      edtim1_str="$edtim1_str""sed 's/PHASE"$label"/PHASE "$this_label"/' | "
      col=`expr $col + 1`
   done

   edtim1_str="$edtim1_str""sed 's/PHASE"$next_label"/PHASE"

   chi2_prev=`head -$m acc_WRAPs.dat | tail -1 | awk -v cvar="$col" '{print $cvar}'`

   # ********** CHECK variable names and positions, and that the TOA list is accurate
   echo $edtim1_str > edtim1


   # Make a script for replacing the PHASE flags and run it
   echo "0/' > trial.tim " > edtim2 ; paste edtim1 edtim2 -d " " > edtim ; sh edtim
   # Run tempo on this file
   tempo trial.tim -f $ephem -w 
	
   #---------------------#
	 
   # now, make resulting ephemeris the new ephemeris
   
   cat $fitephem | grep -v NITS > trial2.par
   echo NITS 1 >> trial2.par
   
   # run tempo on this
   
   tempo trial2.tim -f trial2.par
	 
   # look at residuals
   echo 
   echo "Did iteration $m out of $n."
   echo $acc_combination
   
   /homes/pfreire/bin/plotres
	 
	 
   m=`expr $m + 1`

done

exit
