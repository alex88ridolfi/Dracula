#!/bin/sh

##### (1) Entries that must be updated each time this script is run

# These include the total list of phase gap identifiers used the .tim file. One could grep them from there, but the order is important.
echo PHASE0 > gaps.txt
echo PHASEA >> gaps.txt
echo PHASEB >> gaps.txt
echo PHASEC >> gaps.txt
echo PHASED >> gaps.txt
echo PHASEE >> gaps.txt
echo PHASEF >> gaps.txt
echo PHASEG >> gaps.txt
echo PHASEH >> gaps.txt
echo PHASEI >> gaps.txt
echo PHASEJ >> gaps.txt
echo PHASEK >> gaps.txt
echo PHASEL >> gaps.txt
echo PHASEM >> gaps.txt


number_gaps=`wc -l < gaps.txt`
# add 1, because we start counters below at 1*/
number_gaps=`expr $number_gaps + 1`

##### (2) Entries that can optionally be updated each time this script is run

# inner loops continue as long as chi2 is below this value
chi2_threshold="2.0"

##### (3) Entries that only need to be set at the beginning

# specify version of TEMPO we're using
# path to $TEMPO directory, which contains tempo.cfg, obsys.dat, etc.
TEMPO=/homes/pfreire/tempo_M2/tempo
# path to tempo executable
alias tempo=$TEMPO/tempo

# specify where we are--this is the directory where we want to write our results.
# Default the directory where script is. This directory must contain the ephemeris, TOA list and acc_WRAPs.dat
basedir=$PWD

# specify where we want to run this (RAM disk, like '/dev/shm/timing/')
rundir=/dev/shm/AA

# specify the files we are going to work with
# (.par and .tim file names--these files should be in your basedir) - DON'T name it "trial.tim"
# Examples given of TOA file and initial ephemeris are given in this repository
ephem=47TucAA.par
timfile=47TucAA.tim
# Name the resulting ephemeris (the top of the previous ephem file, plus .par)
rephem=J0024-7205AA.par

# Check whether acc_WRAPs.dat exists (with result from previous run). If not, and you're starting from scratch, uncomment this line
echo "0 0 0" > acc_WRAPs.dat

##### YOU SHOULD NOT NEED TO EDIT BEYOND THIS LINE

# remove previous rundir, make new one, copy files there and start calculations there

rm -rf $rundir
mkdir $rundir
cp gaps.txt acc_WRAPs.dat $ephem $timfile $rundir

# go to rundir and start calculation

cd $rundir

start=`date`

#
touch F1_positives.dat

# set the counter that will go through these solutions
n=1
# set the total counter for the number of tempo runs
t=0
# set total counter for the number of tempo runs with chi2 better than the margin
l=0
# set number of solutions found
s=0

# Arbitrary positions we're sampling for finding new solutions
z1=-5
z2=5

while [ "$n" -gt 0 ]
      # this is the outer loop, where we cycle through the acceptable solutions.
      # We'll keep doing this until there is only one solution left
do

    # update the iteration number
    l=`expr $l + 1`

    # ***** First step: read the first line, the one with the lowest chi2
    head -1 acc_WRAPs.dat > line_complete.txt

    # Take out two last values to make list with phase numbers only
    awk '{$NF=""; print $0}' line_complete.txt | awk '{$NF=""; print $0}' > line.txt

    # Store this in an env. variable
    acc_combination=`cat line.txt`
    
    # *****  Second step: decapitate acc_WRAPs.dat, so that this combination is not processed again
    tail -n +2 acc_WRAPs.dat > WRAPs.dat
    
    # *****  Third step: see how long it is.
    length=`wc line.txt | awk '{print $2}'`
    # add 1, because we start counter below at 1*/
    length=`expr $length + 1`

    # get the previous chi2 here
    chi2_prev=`awk '{print $'$length'}' line_complete.txt`
    
    # *****  Fourth step: a loop, dictated by the number above, where we replace PHASEA with PHASE +l, and replace the JUMP statements above and below by nothing

    # We must start with a clean slate: a trial.tim file that still has all the JUMPs uncommented, and all the PHASEA statements commented
    cp $timfile trial.tim

    # Start the loop
    i=1
    while [ "$i" -lt "$length" ]
    do
	# First, find out which expression is to be replaced 
	ex_to_replace=`head -$i gaps.txt | tail -1`
	
	# Second, find out where it appears in trial.tim file
	line=`sed -n '/'$ex_to_replace'/=' trial.tim`

	# Third: get, from line.txt, the phase number to insert
	phase_number=`awk '{print $'$i'}' line.txt`
	
	# For each element in the loop, replace the comented PHASEA statement by an uncommented statement saying PHASE $phase_number
	# echo Replacing C $ex_to_replace with PHASE $phase_number
	
	sed -i 's/C '$ex_to_replace'/PHASE '$phase_number'/g' trial.tim

	# Now, for two lines before and two lines after, we need to comment the JUMP statements
	line_jump=`expr $line + 2`
	sed -i $line_jump's/.*/C JUMP/' trial.tim

	line_jump=`expr $line - 2`
	sed -i $line_jump's/.*/C JUMP/' trial.tim
	
	# Update the counter #
	i=`expr $i + 1`	  
    done

    # Now, the $i from the previous loop should be smaller than the number of gaps.
    # If it is smaller, find new solutions.
    # If it is the same, we have connected all the gaps. Make sure user knows about this.

    if [ "$i" -lt "$number_gaps" ]
    then

	# Now, let's find more gaps for the next phase number. The syntax here is the same as above.

	# First, find out which expression is to be replaced 
	ex_to_replace=`head -$i gaps.txt | tail -1`
	
	# Second, find out where it appears in trial.tim file
	line=`sed -n '/'$ex_to_replace'/=' trial.tim`

	# Now, uncomment the JUMPs around this
	line_jump=`expr $line + 2`
	sed -i $line_jump's/.*/C JUMP/' trial.tim

	line_jump=`expr $line - 2`
	sed -i $line_jump's/.*/C JUMP/' trial.tim

        echo Iteration $l: starting from solution $acc_combination, with chi2=$chi2_prev   

	# The trial.tim file is ready. This will be the one we will be repeatedly editing over the next few lines.
	# This will be done into a new file (trial_new.tim), otherwise confusion will reign.

	# First, we will test the new gap in 3 points (0, +z, -z). From these three chi2s, we will derive the positions for the best solutions
	
	# ***** Now, calculate the chi2 for PHASE +0
	sed 's/C '$ex_to_replace'/PHASE 0/g' trial.tim > trial_new.tim
	tempo trial_new.tim -f $ephem -w > /dev/null
	t=`expr $t + 1`
	chi2_0=`cat tempo.lis | tail -1 | awk -F= '{print $2}' | awk '{print $1}'`
	
	# Do the same for PHASE $z1
	sed 's/C '$ex_to_replace'/PHASE '$z1'/g' trial.tim > trial_new.tim	
	tempo trial_new.tim -f $ephem -w > /dev/null
	t=`expr $t + 1`
	chi2_1=`cat tempo.lis | tail -1 | awk -F= '{print $2}' | awk '{print $1}'`
	
	# Do the same for PHASE $z2
	sed 's/C '$ex_to_replace'/PHASE '$z2'/g' trial.tim > trial_new.tim	
	tempo trial_new.tim -f $ephem -w > /dev/null
	t=`expr $t + 1`
	chi2_2=`cat tempo.lis | tail -1 | awk -F= '{print $2}' | awk '{print $1}'`
	
	# determine position of minimum (this should be reasonably accurate) by estimating minimum of parabola defined by 0, z1, z2
	
	min=`echo 'scale=0 ; ( '$z2'^2 *('$chi2_0' - '$chi2_1') + '$z1'^2*(-'$chi2_0' + '$chi2_2')) / (2.*('$z2'*('$chi2_0' - '$chi2_1') + '$z1'*(-'$chi2_0' + '$chi2_2'))) / 1.0 ' | bc -l`
	
	# Now, let's calculate the chi2 for the best (minimum) phase
	
	sed 's/C '$ex_to_replace'/PHASE '$min'/g' trial.tim > trial_new.tim
        tempo trial_new.tim -f $ephem -w > /dev/null
	t=`expr $t + 1`
        chi2=`cat tempo.lis | tail -1 | awk -F= '{print $2}' | awk '{print $1}'`
	# check whether the F1 is negative to more than 2 sigma
	# f=`grep F1 $rephem | awk '{print $2"/"$4" < 2.0"}' | bc -l`
	# Commented last line out because the test pulsar is in a Globular cluster
        f=1	
	# Comparison between two real numbers
	chi=`echo $chi2' < '$chi2_threshold | bc -l`
	
	# If chi2 is smaller than threshold, write to WRAPs.dat
	if [ "$chi" -eq "1" ]
	then
	    if [ "$f" -eq "1" ]
	    then
		echo Sol. $acc_combination _$min_ : chi2 = $chi2
		echo $acc_combination $min $chi2 $chi2_prev >> WRAPs.dat
	    else
		echo "F1 is positive to more than 2 sigma"
		echo $acc_combination $z $chi2 $chi2_prev >> F1_positives.dat
	    fi
        else
	    echo "chi2 too large"
        fi
	 	
	# **************** Do cycle going up in phase count
	
	z=`expr $min + 1`
	chi=1
	while [ "$chi" -eq 1 ]
	do
	    
	    sed 's/C '$ex_to_replace'/PHASE '$z'/g' trial.tim > trial_new.tim	    
            tempo trial_new.tim -f $ephem -w > /dev/null
	    t=`expr $t + 1`
            chi2=`cat tempo.lis | tail -1 | awk -F= '{print $2}' | awk '{print $1}'`
	    # check whether the F1 is negative to more than 2 sigma
	    # f=`grep F1 $rephem | awk '{print $2"/"$4" < 2.0"}' | bc -l`
	    # Commented last line out because the test pulsar is in a Globular cluster
            f=1
	    # comparison between two real numbers
            chi=`echo $chi2' < '$chi2_threshold | bc -l` 
	 
	    # If chi2 is smaller than threshold, write to WRAPs.dat
	    if [ "$chi" -eq "1" ]
	    then
		if [ "$f" -eq "1" ]
		then
		    echo Sol. $acc_combination _$z_ : chi2 = $chi2
		    echo $acc_combination $z $chi2 $chi2_prev >> WRAPs.dat
		else
		    echo "F1 is positive to more than 2 sigma"
		    echo $acc_combination $z $chi2 $chi2_prev >> F1_positives.dat
		fi
            else
		echo "chi2 too large"
            fi
	    
            z=`expr $z + 1`
	done
    
	# **************** Do cycle going down in phase count
	
	z=`expr $min - 1`
	chi=1   
	while [ "$chi" -eq 1 ]
	do	 

	    sed 's/C '$ex_to_replace'/PHASE '$z'/g' trial.tim > trial_new.tim	    
            tempo trial_new.tim -f $ephem -w > /dev/null
	    t=`expr $t + 1`
            chi2=`cat tempo.lis | tail -1 | awk -F= '{print $2}' | awk '{print $1}'`
	    # check whether the F1 is negative to more than 2 sigma
	    # f=`grep F1 $rephem | awk '{print $2"/"$4" < 2.0"}' | bc -l`
	    # Commented last line out because the test pulsar is in a Globular cluster
            f=1
	    
	    # Comparison between two real numbers
            chi=`echo $chi2' < '$chi2_threshold | bc -l`

	    # If chi2 is smaller than threshold, write to WRAPs.dat
	    if [ "$chi" -eq "1" ]
	    then
		if [ "$f" -eq "1" ]
		then
		    echo Sol. $acc_combination _$z_ : chi2 = $chi2
		    echo $acc_combination $z $chi2 $chi2_prev >> WRAPs.dat
		else
		    echo "F1 is positive to more than 2 sigma"
		    echo $acc_combination $z $chi2 $chi2_prev >> F1_positives.dat
		fi
            else
		echo "chi2 too large"
            fi
	    
            z=`expr $z - 1`
	done
	
    else
	# If the gap number $i is the same as the number of gaps, then we have reached our objective
	echo "All gaps have been connected!"
	sleep 10
	tempo trial.tim -f $ephem -w > /dev/null
	chi2=`cat tempo.lis | tail -1 | awk -F= '{print $2}' | awk '{print $1}'`
	
	echo $acc_combination $chi2 > $basedir/solution_$l.dat
	cp trial.tim $basedir/solution_$l.tim
	cp $rephem $basedir/solution_$l.par
	s=`expr $s + 1`
	# Note that solution_n.tim runs with $ephem, to produce solution_n.par. The latter ephemeris should run with a version of solution_n.tim where all the PHASE stetements have been commented out.
	# However, the algorithm will continue, to check for the uniqueness of the solution.
    fi

    # re-make acc_WRAPs.dat for next loop, and count the numbers.
    # This is done by sorting on the penultimate column, which has the chi2 from the previous work
    awk '{print $(NF-1)" "$0}' WRAPs.dat | sort -n | cut -f2- -d' ' > acc_WRAPs.dat
    
    n=`wc -l < acc_WRAPs.dat`
done

end=`date`

# cd report on what's been done

echo Made a total of $t trials
echo Of those, a total of $l unique partial solutions had reduced chi2s smaller than $chi2_threshold,
echo  which were stored and processed further.
echo Found $s solution
echo Started $start
echo Ended $end

exit
