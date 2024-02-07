#!/bin/sh

# Things to edit before running the script are indicated with *****

# ***** Specify your chi2 threshold. Program continues while there are any partial solutions with chi2s below this level.
chi2_threshold="2.0"

# ***** specify version of TEMPO we're using
#       a) path to $TEMPO directory, which contains tempo.cfg, obsys.dat, etc.
TEMPO=/homes/pfreire/tempo
#       b) path to tempo executable
alias tempo=$TEMPO/tempo

# ***** Specify where we are--this is the directory where we want to write our results.
#       Default the directory where script is. This directory must contain the ephemeris, TOA list and acc_WRAPs.dat
basedir=$PWD

# ***** Specify where we want to run this (Shared memory  - /dev/shm/something - saves your disk and tons of time)
rundir=/dev/shm/AA

# ***** Specify the files we are going to work with
#       (.par and .tim file names--these files should be in your basedir) - DON'T name it "trial.tim"
#       Examples given of TOA file and initial ephemeris are given in this repository
ephem=47TucAA.par
timfile=47TucAA.tim

# ***** Name the resulting ephemeris (the top of the previous ephem file, plus .par)
rephem=J0024-7205AA.par

# ***** Finally: Edit your mail address here (please change this, otherwise I'll be getting e-mails with your solutions)
address=pfreire@mpifr-bonn.mpg.de

##########################  YOU SHOULD NOT NEED TO EDIT BEYOND THIS LINE  ########################## 

# Function to calculate chi2 for a given rotation number for the last gap 
calculate_chi2() {
    sed 's/C '$ex_to_replace'/PHASE '$1'/g' trial.tim > trial_new.tim
    tempo trial_new.tim -f $ephem -w > /dev/null
    cat tempo.lis | tail -1 | awk -F= '{print $2}' | awk '{print $1}'
}

# Procedure to process solutions with good chi2
process_solution() {
    # See if the chi2 is smaller than the threshold  
        chi=$(echo "$chi2 < $chi2_threshold" | bc -l)

    # If so, process the solution
    if [ "$chi" -eq 1 ]; then
        # If the number of gaps connected by the new solution is the same as the number of gaps, notify the user of the solution
        if [ "$i" -eq "$n_gaps" ]; then
            echo Full solution found! $acc_combination, $z : chi2 = $chi2
            echo $acc_combination $z $chi2 $chi2_prev solution_$l.$z.par > $basedir/solution_$l.$z.dat
            cp $rephem $basedir/solution_$l.$z.par
            # Let the user know a solution has been found
            cat $rephem | mail -s "Solution found" $address
            s=$(expr $s + 1)
        else
            # If the number of connections is smaller, write the solution to WRAPs.dat
            echo Found $acc_combination, $z : chi2 = $chi2
            echo $acc_combination $z $chi2 $chi2_prev >> WRAPs.dat
        fi
    else
        echo "chi2 too large"
    fi
}

# Remove solutions from previous runs (necessary to avoid confusion)
rm -rf solution* list_solutions.dat

# Let's see about acc_WRAPs.dat

# Count the lines in acc_WRAPs.dat
n=`ls acc_WRAPs.dat | wc -l`

echo
if [ "$n" -eq "0" ]
  then
     rm -rf acc_WRAPs.dat
     echo 0 0 0 > acc_WRAPs.dat
     echo "Starting from scratch!"
  else
     echo "Starting from pre-existing list of solutions."
     echo "This only works if you are continuing previously interrupted work"
     echo "or if you have named additional gaps in the previous timfile with GAP tags"
     echo "(for current list of tags, see file gaps.txt)."
     echo "If you changed your time file significantly, or have changed the positions of the tags, this won't work, and you should start from scratch."
     echo "If you want to start from scratch, stop script and delete file acc_WRAPs.dat"
  fi
echo
sleep 5;

# Make sorted file with list of gaps
grep GAP $timfile | awk '{print $2}' | sort > gaps.txt

# set number of gaps
n_gaps=`wc -l < gaps.txt`
# add 1, because we start counters below at 1*/
number_gaps=`expr $n_gaps + 1`

# Count the lines in acc_WRAPs.dat
n=`wc -l < acc_WRAPs.dat`

# remove previous rundir, make new one, copy files there and start calculations there
rm -rf $rundir
mkdir $rundir
cp gaps.txt $ephem $timfile $rundir
cp acc_WRAPs.dat $rundir

# go to rundir and start calculation
cd $rundir
start=`date`

# set total counter for the number of tempo runs with chi2 better than the margin
l=0
# set number of solutions found
s=0
# Arbitrary positions we're sampling for finding new solutions
z1=-5
z2=5

while [ "$n" -gt 0 ]
      # this is the outer loop, where we cycle through the acceptable solutions.
      # We'll keep doing this until there are no partial solutions left
do
    # Let's now find out how many lines we want to do in a row. 1% of the lines is a good target, I think.
    # This will reduce the number of sorts by a factor k. However, it could slightly delay finding the solution.
    if [ "$n" -gt 100000 ]
    then
	k=1000
	k2=1001
    else
	if [ "$n" -gt 10000 ]
	then
	    k=100
	    k2=101
	else
	    if [ "$n" -gt 1000 ]
	    then
		k=10
		k2=11
	    else
		k=1
		k2=2
	    fi	
	fi
    fi

    kc=0

    # decapitate acc_WRAPs.dat by k, so that the first k combinations are not processed again
    tail -n +$k2 acc_WRAPs.dat > WRAPs.dat

    # make smaller file with first k lines
    head -$k acc_WRAPs.dat > top_acc_WRAPs.dat
    
    # Let's now process these k combinations, which are still in acc_WRAPs.dat
    while [ "$kc" -lt "$k" ]
    do
	kc=`expr $kc + 1`
	l=`expr $l + 1`

	# First step: read the first line, the one with the lowest chi2
	head -$kc top_acc_WRAPs.dat | tail -1 > line_complete.txt
	
	# Take out two last values to make list with phase numbers only
	awk '{$NF=""; print $0}' line_complete.txt | awk '{$NF=""; print $0}' > line.txt
	
	# Store this in an env. variable
	acc_combination=`cat line.txt`
		
	# Third step: see how long it is.
	length=`wc line.txt | awk '{print $2}'`
	# add 1, because we start counter below at 1*/
	length=`expr $length + 1`
	
	# get the previous chi2 here
	chi2_prev=`awk '{print $'$length'}' line_complete.txt`

	echo Iteration $l, $kc: processing solution $acc_combination, with chi2 = $chi2_prev
	
	# Fourth step: a loop, dictated by the number above, where we replace PHASEA with PHASE +l, and replace the JUMP statements above and below by nothing
	
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
	
	# The trial.tim file is ready. This will be the one we will be repeatedly editing over the next few lines.
	# This will be done into a new file (trial_new.tim), otherwise confusion will reign.
	
	# First, we will test the new gap in 3 points (0, z1, z2).
        chi2_0=$(calculate_chi2 0)
        chi2_1=$(calculate_chi2 $z1)
	chi2_2=$(calculate_chi2 $z2)
	
	# From these values, determine position of minimum (this should be reasonably accurate) by estimating minimum of parabola defined by 0, z1, z2
	min=`echo 'scale=0 ; ( '$z2'^2 *('$chi2_0' - '$chi2_1') + '$z1'^2*(-'$chi2_0' + '$chi2_2')) / (2.*('$z2'*('$chi2_0' - '$chi2_1') + '$z1'*(-'$chi2_0' + '$chi2_2'))) / 1.0 ' | bc -l`
	
	# Now, let's calculate the chi2 for the best (minimum) phase
	z=$min
        # Calculate chi2 for this z 	
        chi2=$(calculate_chi2 $z)	
	# Check if chi2 is good, if so then process solution
        process_solution

	# Do cycle going up in phase count
	z=`expr $min + 1`
	chi=1
	while [ "$chi" -eq 1 ]
	do 
	    chi2=$(calculate_chi2 $z) 
	    process_solution
	    z=`expr $z + 1`
	done
	
	# Do cycle going down in phase count
	z=`expr $min - 1`
	chi=1   
	while [ "$chi" -eq 1 ]
	do	 
	    chi2=$(calculate_chi2 $z)
	    process_solution 
            z=`expr $z - 1`
	done	
    done
    
    # re-make acc_WRAPs.dat for next k cycle.
    # This is done by sorting on the penultimate column, which has the chi2 from the previous work
    awk '{print $(NF-1)" "$0}' WRAPs.dat | sort -n | cut -f2- -d' '  > acc_WRAPs.dat
    echo Did the sort.

    # The file is built by sorting WRAPs.dat, which has the partial solutions not processed in the previous loop,
    # plus the new solutions found during the last loop.

    # Let's now save one's work, in case there are problems with the computer
    if [ "$k" -gt "10" ]
    then
	cp acc_WRAPs.dat $basedir
    fi

    # Update n with number of remaining solutions  
    n=`wc -l < acc_WRAPs.dat`
done

end=`date`

cd $basedir

# At this stage, acc_WRAPs.dat should be empty. What we can do is to make a new one from the solution(s) found, in order to continue work
# Either with extra gap tags in same data set, or with new ones around a new data set. 

# First, we make a sorted list of solution
cat solution_*dat | awk '{print $(NF-2)" "$0}' | sort -n | cut -f2- -d' ' > list_solutions.dat

# Second, chop off the last column to make the new acc_WRAPs.dat
awk '{NF--; print}' list_solutions.dat > acc_WRAPs.dat

# Make list of solutions with pointers to solutions written and report on what's been done
echo Of those, a total of $l unique solutions had reduced chi2s smaller than $chi2_threshold,
echo  which for that were stored and processed further.
echo Found $s solutions.
echo Started $start
echo Ended $end

exit
