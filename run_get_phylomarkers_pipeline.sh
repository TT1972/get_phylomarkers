#!/usr/bin/env bash

#: PROGRAM: run_get_phylomarkers_pipeline.sh
#: AUTHORS: Pablo Vinuesa, Center for Genome Sciences, CCG-UNAM, Mexico
#:          https://www.ccg.unam.mx/~vinuesa/
#           Bruno Contreras Moreira, EEAD-CSIC, Zaragoza, Spain
#           https://www.eead.csic.es/compbio
#
#: DISCLAIMER: programs of the GET_PHYLOMARKERS package are distributed in the hope that they will be useful, 
#              but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
#              See the GNU General Public License for more details. 
#
#: LICENSE: This software is freely available under the GNU GENERAL PUBLIC LICENSE v.3.0 (GPLv3)
#           see https://github.com/vinuesa/get_phylomarkers/blob/master/LICENSE.txt
#
#: AVAILABILITY: freely available from GitHub @ https://github.com/vinuesa/get_phylomarkers
#                and DockerHub @ https://hub.docker.com/r/vinuesa/get_phylomarkers
#
#: PROJECT START: April 2017; This is a wrapper script to automate the whole process of marker selection
#                     and downstream phylogenomic analyses.
#
#: AIM: select optimal molecular markers for phylogenomics and population genomics from orthologous gene clusters computed by GET_HOMOLOGUES,
#           which is freely available from GitHub @ https://github.com/eead-csic-compbio/get_homologues
#
#: OUTPUT: multiple sequence alignments (of protein and DNA sequences) of selected markers, gene trees, and species trees 
#              inferred from gene trees (ASTRAL/ASTER), and the concatenated supermatrix of top-ranking markers, 
#              along with graphics and tables summarizing the results of the pipeline obtained at the different filtering steps.
# 
#: MANUAL: a detailed manual and tutorial are available here: https://vinuesa.github.io/get_phylomarkers/
# 
#: CITATION / PUBLICATION: If you use this software in your own publications, please cite the following paper:
#    Vinuesa P, Ochoa-Sanchez LE, Contreras-Moreira B. GET_PHYLOMARKERS, a Software Package to Select Optimal Orthologous Clusters for Phylogenomics 
#    and Inferring Pan-Genome Phylogenies, Used for a Critical Geno-Taxonomic Revision of the Genus Stenotrophomonas. 
#    Front Microbiol. 2018 May 1;9:771. doi:10.3389/fmicb.2018.00771. 
#    eCollection 2018. PubMed PMID: 29765358; PubMed Central PMCID: PMC5938378.
# ===============================================================================================================

# DEVFLAGS: <FIXME>; <SOLVED>; <TODO>; <DONE>

# Set Bash strict mode
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
#set -x # enables debugging output to trace the execution flow; Print commands and their arguments as they are executed. Also executed as bash -x script
set -e  # NOTES: all "${distrodir}"/* calls fail unless they are wrapped in the following code
        #   { "${distrodir}"/run_parallel_cmmds.pl faaed 'add_nos2fasta_header.pl $file > ${file}no' "$n_cores" &> /dev/null && return 0; }
	# Also added extended error and return 0 calls to the functions in get_phylomarkers_fun_lib and main script
set -u
set -o pipefail

progname=${0##*/} # run_get_phylomarkers_pipeline.sh
VERSION='2.8.4.0_2024-04-20'
                         		   
# Set GLOBALS
# in Strict mode, need to explicitly set undefined variables to an empty string var=''
DEBUG=0
wkdir=$(pwd) #echo "# working in $wkdir"
PRINT_KDE_ERR_MESSAGE=0
logdir=$(pwd)
dir_suffix=''
lmsg=''
gene_tree_ext=''
no_kde_outliers=''
no_kde_ok=''
lmap_sampling=2000

declare -A filtering_results_h=()
declare -a filtering_results_kyes_a=()

declare -A output_files_h=()
declare -a output_files_a=()

declare -A figs_h=()
declare -a figs_a=()

declare -A aln_models_h=()
declare -a aln_models_a=() 

declare -A aln_lmappings_h=()
declare -a aln_lmappings_a=()

declare -A alns_passing_lmap_and_suppval_h=()
declare -a alns_passing_lmap_and_suppval_a=()

declare -A alnIDs2names=()


min_bash_vers=4.4 # required for:
                  # 1. mapfile -t array <(cmd); see SC2207
		  # 2.  printf '%(%F)T' '-1' in print_start_time; and 
                  # 3. passing an array or hash by name reference to a bash function (since version 4.3+), 
		  #    by setting the -n attribute
		  #    see https://stackoverflow.com/questions/16461656/how-to-pass-array-as-an-argument-to-a-function-in-bash

DATEFORMAT_SHORT="%d%b%y"
TIMESTAMP_SHORT=$(date +${DATEFORMAT_SHORT})

DATEFORMAT_HMS="%H:%M:%S"
#TIMESTAMP_HMS=$(date +${DATEFORMAT_HMS})

TIMESTAMP_SHORT_HMS=$(date +${DATEFORMAT_SHORT}-${DATEFORMAT_HMS})

#>>> set colors in bash
# ANSI escape codes
# Black        0;30     Dark Gray     1;30
# Red          0;31     Light Red     1;31
# Green        0;32     Light Green   1;32
# Brown/Orange 0;33     Yellow        1;33
# Blue         0;34     Light Blue    1;34
# Purple       0;35     Light Purple  1;35
# Cyan         0;36     Light Cyan    1;36
# Light Gray   0;37     White         1;37

RED='\033[0;31m'
LRED='\033[1;31m'
#GREEN='\033[0;32m'
#YELLOW='\033[1;33m'
#BLUE='\033[0;34m'
#LBLUE='\033[1;34m'
#CYAN='\033[0;36m'
NC='\033[0m' # No Color => end color
#printf "${RED}%s${NC} ${GREEN}%s${NC}\n" "I like" "GitHub"


#---------------------------------------------------------------------------------#
#>>>>>>>>>>>>>>>>>>>>>>>>>>>> FUNCTION DEFINITIONS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<#
#---------------------------------------------------------------------------------#

function check_bash_version()
{
   bash_vers=$(bash --version | head -1 | awk '{print $4}' | sed 's/(.*//' | cut -d. -f1,2)
   
   if [ 1 -eq "$(echo "$bash_vers < $min_bash_vers" | bc)" ]; 
   then 
       msg "FATAL: you are running acient bash v${bash_vers}, and version >= $min_bash_vers, is required" ERROR RED && exit 1
   else
       return 0
   fi  
}
#-----------------------------------------------------------------------------------------

function print_start_time()
{
   #echo -n "[$(date +%T)] "
   printf '%(%T )T' '-1' # requires Bash >= 4.3
}
#-----------------------------------------------------------------------------------------

function set_pipeline_environment()
{
  if [[ "$OSTYPE" == "linux-gnu" ]]
  then
    local wkd scriptdir distrodir bindir OS no_cores 
    wkd=$(pwd)
    scriptdir=$(readlink -f "${BASH_SOURCE[0]}")
    distrodir=$(dirname "$scriptdir") #echo "scriptdir: $scriptdir|basedir:$distrodir|OSTYPE:$OSTYPE"
    bindir="$distrodir/bin/linux"
    OS='linux'
    no_cores=$(awk '/^processor/{n+=1}END{print n}' /proc/cpuinfo)
    #local  rlibs=`for p in $(R -q -e 'print(.libPaths())'); do if [[ "$p" =~ '/' ]]; then echo -n "$p:"; fi; done; echo -n "$wkd"/"$distrodir/lib/R"`
    #export R_LIBS_SITE="$rlibs"
  elif [[ "$OSTYPE" == "darwin"* ]]
  then
    # get abs path of script as in 
    # https://stackoverflow.com/questions/5756524/how-to-get-absolute-path-name-of-shell-script-on-macos
    local wkd scriptdir distrodir bindir OS no_cores
    wkd=$(pwd)
    scriptdir=${BASH_SOURCE[0]}
    distrodir=$(cd "$(dirname "$scriptdir")" || { msg "ERROR: could not cd into $scriptdir" ERROR RED && exit 1 ; }; pwd -P)
    distrodir="$wkd"/"$distrodir"
    bindir="$distrodir/bin/macosx-intel"
    OS='darwin'
    no_cores=$(sysctl -n hw.ncpu)
    #local  rlibs=`for p in $(R -q -e 'print(.libPaths())'); do if [[ "$p" =~ '/' ]]; then echo -n "$p:"; fi; done; echo -n "$distrodir/lib/R"`
    #export R_LIBS_SITE="$rlibs"
  else
    echo "ERROR: untested OS $OSTYPE, exit"
    exit 1
  fi
  echo "$distrodir $bindir $OS $no_cores"
}
#-----------------------------------------------------------------------------------------

function check_dependencies()
{
    #local VERBOSITY="$1"
    # check if scripts are in path; if not, set flag
    (( DEBUG > 0 )) && msg " => working in ${FUNCNAME[0]} ..." DEBUG NC
    
    local prog bin
    system_binaries=(bash R perl awk bc cut grep sed sort uniq Rscript find)

    for prog in "${system_binaries[@]}" 
    do
       bin=$(type -P "$prog")
       if [ -z "$bin" ]; then
          echo
	  printf "${RED}%s${NC}\n"  "# ERROR: system binary $prog is not in \$PATH!"
	  printf "${LRED}%s${NC}\n" " >>> you will need to install $prog for $progname to run on $HOSTNAME"
	  printf "${LRED}%s${NC}\n" " >>> will exit now ..."

          exit 1  # Exit with non-zero status
       else
	  (( DEBUG > 0 )) && msg " <= exiting ${FUNCNAME[0]} ..." DEBUG NC
          return 0
       fi
    done
}
#-----------------------------------------------------------------------------------------

function check_scripts_in_path()
{
    (( DEBUG > 0 )) && msg " => working in ${FUNCNAME[0]} ..." DEBUG NC

    local bash_scripts perl_scripts R_scripts prog bin distrodir not_in_path user

    distrodir=$1
    user=$2
    not_in_path=0

   (( DEBUG > 0 )) && msg "check_scripts_in_path() distrodir: $distrodir" DEBUG NC
    
    bash_scripts=(run_parallel_molecClock_test_with_paup.sh)
    perl_scripts=(run_parallel_cmmds.pl add_nos2fasta_header.pl pal2nal.pl rename.pl concat_alignments.pl \
      add_labels2tree.pl convert_aln_format_batch_bp.pl popGen_summStats.pl)
    R_scripts=( run_kdetrees.R compute_suppValStas_and_RF-dist.R )

    # check if scripts are in path; if not, set flag
    for prog in "${bash_scripts[@]}" "${perl_scripts[@]}" "${R_scripts[@]}"
    do
       bin=$(type -P "$prog")
        if [ -z "$bin" ]; then
            echo
            if [ "$user" == "root" ]; then
	            msg "# WARNING: script $prog is not in \$PATH!" WARNING LRED
	            msg " >>>  Will generate a symlink from /usr/local/bin or add it to \$PATH" WARNING CYAN
	            not_in_path=1
	        else
	            msg "# WARNING: script $prog is not in \$PATH!" WARNING LRED
	            msg " >>>  Will generate a symlink from $HOME/bin or add it to \$PATH" WARNING CYAN
	            not_in_path=1
	        fi
        fi
    done

    # if flag $not_in_path -eq 1, then either generate symlinks into $HOME/bin (if in $PATH) or export $distrodir to PATH
    if (( not_in_path == 1 ))
    then
        if [[ "$user" == "root" ]]
        then
       	    if [ ! -d /usr/local/bin ]
       	    then
          	   msg "Could not find a /usr/local/bin directory for $user ..."  WARNING CYAN
	  	       msg " ... will update PATH=$distrodir:$PATH"  WARNING CYAN
	  	       export PATH="${distrodir}:${PATH}" # prepend $ditrodir to $PATH
       	    fi

       	   # check if $HOME/bin is in $PATH
       	    if echo "$PATH" | sed 's/:/\n/g' | grep "/usr/local/bin$" &> /dev/null
       	    then
          	   msg "Found dir /usr/local/bin for $user in \$PATH ..." WARNING CYAN
          	   msg " ... will generate symlinks in /usr/local/bin to all scripts in $distrodir ..." WARNING CYAN
          	   ln -s "$distrodir"/*.sh /usr/local/bin &> /dev/null
          	   ln -s "$distrodir"/*.R /usr/local/bin &> /dev/null
          	   ln -s "$distrodir"/*.pl /usr/local/bin &> /dev/null
       	    else
          	   msg " Found dir /usr/local/bin for $user, but it is NOT in \$PATH ..." WARNING CYAN
          	   msg " ... updating PATH=$PATH:$distrodir" WARNING CYAN
	  	       export PATH="${distrodir}:${PATH}" # prepend $distrodir to $PATH
       	    fi
        else       
       	    if [ ! -d "$HOME"/bin ]
       	    then
          	   msg "Could not find a $HOME/bin directory for $user ..."  WARNING CYAN
	  	       msg " ... will update PATH=$distrodir:$PATH"  WARNING CYAN
	  	       export PATH="${distrodir}:${PATH}" # prepend $ditrodir to $PATH
       	    fi

       	   # check if $HOME/bin is in $PATH
       	    if echo "$PATH" | sed 's/:/\n/g'| grep "$HOME/bin$" &> /dev/null
       	    then
          	   msg "Found dir $HOME/bin for $user in \$PATH ..." WARNING CYAN
          	   msg " ... will generate symlinks in $HOME/bin to all scripts in $distrodir ..." WARNING CYAN
          	   ln -s "$distrodir"/*.sh "$HOME"/bin &> /dev/null
          	   ln -s "$distrodir"/*.R "$HOME"/bin &> /dev/null
          	   ln -s "$distrodir"/*.pl "$HOME"/bin &> /dev/null
          	   #ln -s $distrodir/rename.pl $HOME/bin &> /dev/null
       	    else
          	   msg " Found dir $HOME/bin for $user, but it is NOT in \$PATH ..." WARNING CYAN
          	   msg " ... updating PATH=$PATH:$distrodir" WARNING CYAN
	  	       export PATH="${distrodir}:${PATH}" # prepend $distrodir to $PATH
       	    fi
        fi
    fi
    (( DEBUG > 0 )) && msg " <= exiting ${FUNCNAME[0]} ..." DEBUG NC
    return 0
}
#-----------------------------------------------------------------------------------------

function set_bindirs()
{
    (( DEBUG > 0 )) && msg " => working in ${FUNCNAME[0]} ..." DEBUG NC
    # receives: $bindir
    local bindir
    bindir=$1
#   not_in_path=1

#   # prepend $bindir to $PATH in any case, to ensure that the script runs with the distributed binaries in $bindir
    export PATH="${bindir}:${PATH}"

#    bins=( clustalo FastTree parallel Phi paup consense )
#
#    for prog in "${bins[@]}"
#    do
#       bin=$(type -P $prog)
#       if [ -z $bin ]
#       then
#          echo
#          printf "${LRED}# $prog not found in \$PATH ... ${NC}\n"
#	        not_in_path=1
#       fi
#   done
#
#    # check if scripts are in path; if not, set flag
#   if [ $not_in_path -eq 1 ]
#   then
#   	   printf "${CYAN} updating PATH=$PATH:$bindir ${NC}\n"
#   	   #export PATH=$PATH:$bindir # append $HOME/bin to $PATH, (at the end, to not interfere with the system PATH)
#	   # we do not export, so that this PATH update lasts only for the run of the script,
#	   # avoiding a longer-lasting alteration of $ENV;
#	   export PATH="${bindir}:${PATH}" # prepend $bindir to $PATH to ensure that the script runs with the distributed binaries
#   fi
   #echo $setbindir_flag
   (( DEBUG > 0 )) && msg " <= exiting ${FUNCNAME[0]}..." DEBUG NC
   return 0
}
#-----------------------------------------------------------------------------------------

function print_software_versions()
{
   echo 
   msg ">>> Software versions run by $progname version $VERSION" PROGR LBLUE
    
   bash --version | grep bash
   check_bash_version
   echo '-------------------------'
   perl -v | grep version
   echo '-------------------------'
   R --version | grep version | grep R
   echo '-------------------------'
   parallel --version | grep 'GNU parallel' | grep -v warranty
   echo '-------------------------'
   bc --version | grep bc
   echo '-------------------------'
   "${bindir}"/paup --version
   echo '-------------------------'
   "${bindir}"/FastTree &> FT.tmp && FT_vers=$(head -1 FT.tmp | sed 's/Usage for FastTree //; s/://') && rm FT.tmp
   echo "FastTree v.${FT_vers}"
   echo '-------------------------'
   "${bindir}"/iqtree --version | head -1
   echo '-------------------------'
   echo "consense, pars and seqboot v.3.69"
   echo '-------------------------'
   clustalo_version=$("${bindir}"/clustalo --version)
   echo "clustalo v.${clustalo_version}"
   echo '-------------------------'
   echo
   
   exit 0
}
#-----------------------------------------------------------------------------------------

function print_codontables()
{
  cat <<CODONTBL
    1  Universal code (default)
    2  Vertebrate mitochondrial code
    3  Yeast mitochondrial code
    4  Mold, Protozoan, and Coelenterate Mitochondrial code
       and Mycoplasma/Spiroplasma code
    5  Invertebrate mitochondrial
    6  Ciliate, Dasycladacean and Hexamita nuclear code
    9  Echinoderm and Flatworm mitochondrial code
   10  Euplotid nuclear code
   11  Bacterial, archaeal and plant plastid code
   12  Alternative yeast nuclear code
   13  Ascidian mitochondrial code
   14  Alternative flatworm mitochondrial code
   15  Blepharisma nuclear code
   16  Chlorophycean mitochondrial code
   21  Trematode mitochondrial code
   22  Scenedesmus obliquus mitochondrial code
   23  Thraustochytrium mitochondrial code

CODONTBL

   exit 0

}
#-----------------------------------------------------------------------------------------

function print_usage_notes()
{
   cat <<USAGE

   $progname v$VERSION extensive Help and details on the search modes and models.

   1. Start the run from within the directory holding core gene clusters generated by 
      get_homologues.pl -e -t number_of_genomes or compare_clusters.pl -t number_of_genomes

      NOTE: Both .faa and .fna files are required to generate codon alignments from DNA fasta files. This
        means that two runs of compare_clusters.pl (from the get_homologues package) are required, one of them
        using the -n flag. See GET_HOMOLOGUES online help http://eead-csic-compbio.github.io/get_homologues/manual/ 

   2. $progname is intended to run on a collection of single-copy sequence clusters from different species or strains.

      NOTES: An absolute minimum of 4 distinct genomes are required.
       However, the power of the pipeline for selecting optimal genome loci
	  for phylogenomics improves when a larger number of genomes are available
	  for analysis. Reasonable numbers lie in the range of 10 to 200 distinct genomes
	  from multiple species of a genus, family, order or phylum.
	  The pipeline may not perform satisfactorily with very distant genome sequences,
	  particularly when sequences with significantly distinct nucleotide or aminoacid
	  compositions are used. This type of sequence heterogeneity is well known to
	  cause systematic bias in phylogenetic inference.

   3. On the locus filtering criteria. $progname uses a hierarchical filtering scheme, as follows:

      i) Detection of recombinant loci. Codon or protein alignments (depending on runmode)
          are first screened with phi(w) for the presence of potential recombinant sequences.
	  It is a well established fact that recombinant sequences negatively impact
	  phylogenetic inference when using algorithms that do not account for the effects
	  of this evolutionary force. The permutation test with 1000 permutations is used
	  to compute the p-values. These are considerd significant if < 0.05.

      ii) Detection of trees deviating from the expectation of the (multispecies) coalescent.
           The next filtering step is provided by the kdetrees test, which checks the distribution of
           topologies, tree lengths and branch lenghts. kdetrees is a non-parametric method for
	   estimating distributions of phylogenetic trees, with the goal of identifying trees that
	   are significantly different from the rest of the trees in the sample. Such "outlier"
	   trees may arise for example from horizontal gene transfers or gene duplication
	   (and subsequent neofunctionalization) followed by differential loss of paralogues among
	   lineages. Such processes will cause the affected genes to exhibit a history distinct
	   from those of the majority of genes, which are expected to be generated by the
	   (multispecies) coalescent as species or populations diverge. Alignments producing
	   significantly deviating trees in the kdetrees test are discarded.

	    * Parameter for controlling kdetrees stingency:
	    -k <real> kde stringency (0.7-1.6 are reasonable values; less is more stringent)
	              [default: $kde_stringency]

      iii) Phylogenetic signal content. 
            The alignments passing the two previous filters are subjected to maximum likelihood 
	    (ML) tree searches with FastTree or IQ-TREE to infer the corresponding ML gene trees. 
	    The phylogenetic signal of these trees is computed from the Shimodair-Hasegawa-like 
	    likelihood ratio test (SH-alrt) of branch support values, which vary between 0-1. 
	    The support values of each internal branch or bipartition are parsed to compute the 
	    mean support value for each tree. Trees with a mean support value below a cutoff 
	    threshold are discarded.

         * Parameters controlling filtering based on mean support values.
         -m <real> min. average support value (0.7-0.8 are reasonable values)
	           for trees to be selected [default: $min_supp_val]

      iv) On tree searching: From version 2.0 onwards, $progname performs tree searches using
          either the FastTree (FT) or IQ-TREE (IQT) fast ML tree search algorithms,
	  controlled with the -A <F|I> option [default: $search_algorithm]

       a) FT searches:
	  FT meets a good compromise between speed and accuracy, runnig both
	  with DNA and protein sequence alignments. It computes the above-mentioned
	  Shimodaria-Hasegawa-like likelihood ratio test of branch support values.
	  A limitation though, is that it implements only tow substitution models.
	  However, for divergent sequences of different species within a bacterial taxonomic
	  genus or family, our experience has shown that almost invariably the GTR+G model
	  is selected by jmodeltest2, particularly when there is base frequency heterogeneity.
	  The GTR+G+CAT is the substitution model used by $progname calls of FastTree on codon
	  alignments. From version 2.0 onwards, $progname can compute gene trees wit FT using
	  differetn levels of tree search intensity as defined with the -T parameter, both
	  during the gene-tree and species-tree estimation phases.

	   high:   -nt -gtr -bionj -slow -slownni -gamma -mlacc 3 -spr $spr -sprlength $spr_length
	   medium: -nt -gtr -bionj -slownni -gamma -mlacc 2 -spr $spr -sprlength $spr_length
	   low:    -nt -gtr -bionj -gamma -spr $spr -sprlength $spr_length
           lowest: -nt -gtr -gamma -mlnni 4

	   where -s \$spr and -l \$spr_length can be set by the user.
	   The lines above show their default values.

	   The same applies for tree searches on concatenated codon alignments.
	   Note that these may take a considerable time (up to several hours)
	   for large datasets (~ 100 taxa and > 300 concatenated genes).

	   For protein alignments, the search parameters are the same, only the model changes to LG

	   Please refer to the FastTree manual for the details.

       b) IQT searches:
          Our benchmark analyses have shown that IQ-TREE (v1.6.1) runs quickly enough when the '-fast'
	  flag is passed to make it feasible to include a modelselection step withouth incurring in 
	  prohibitively long computation times. Combined with its superior tree-searching algorithm, 
	  makes IQT the clear winner in our benchmarks. Therefore, from version 2.0 (22Jan18) onwards,
	  $progname uses IQT as its default tree searching algorithm, both for the estimation of
	  gene-trees and the species-tree (from the concatenated, top-scoring alignments), now using
	  model selection in both cases (v 1.9 only used model selection and IQT for supermatrix search).
	  
	  However, the number of models evaluated by ModelFinder (integrated in IQ-TREE) differ for the
	  gene-tree and species-tree search phases, as detailed below: 

	-IQT gene-tree searches (hard-coded): -T <high|medium|low|lowest> [default: $search_thoroughness]
	  high:   -m MFP -nt 1 -alrt 1000 -fast [ as jModelTest]
	  medium: -mset K2P,HKY,TN,TNe,TIM,TIMe,TIM2,TIM2e,TIM3,TIM3e,TVM,TVMe,GTR -m MFP -nt 1 -alrt 1000 -fast
	  low:	  -mset K2P,HKY,TN,TNe,TVM,TVMe,TIM,TIMe,GTR -m MFP -nt 1 -alrt 1000 -fast
	  lowest: -mset K2P,HKY,TN,TNe,TVM,TIM,GTR -m MFP -nt 1 -alrt 1000 -fast

	  all gene trees are run in parallel under the modelset with the following parameters: 
	    -mset X,Y,Z -m MFP -nt 1 -alrt 1000 -fast

	-IQT species-tree searches on the supermatrix: 
	      -S <string> comma-separated list of base models to be evaluated by IQ-TREE
	         when estimating the species tree from the concatenated supermatrix.
		 If no -S is passed, then sinlge default models are used, as shown below
              <'JC,F81,K2P,HKY,TrN,TNe,K3P,K81u,TPM2,TPM2u,TPM3,TPM3u,
	      TIM,TIMe,TIM2,TIM2e,TIM3,TIM3e,TVM,TVMe,SYM,GTR'>              for DNA alignments    [default: $IQT_DNA_models]
              <'BLOSUM62,cpREV,Dayhoff,DCMut,FLU,HIVb,HIVw,JTT,JTTDCMut,LG,
                mtART,mtMAM,mtREV,mtZOA,Poisson,PMB,rtREV,VT,WAG'>           for PROT alignments   [default: $IQT_PROT_models]
		
          In addition, if -T high, $progname will launch -N <integer> [default: $nrep_IQT_searches] independent IQT searches
	     on the supermatrix of concatenated top-scoring markers.

    v) Running the pipeline in population-genetics mode (-R 2 -t DNA): 
       When invoked in popGen mode (-R 2), the pipeline will perform the same 4 initial steps as in phylo mode (-R 1): 
          1. generate codon alginments
          2. chech them for the presence of recombinant sequences
          3. estimate phylogenetic trees from non-recombinant alignments
          4. filter gene trees for outliers with kdetrees test
	  
	  The filtered alignments (non-recombinant and non-outlier) will then enter into the DNA polymorphims analysis,
	    which involves computing basic descriptive statistics from the alignments as well as performing the popular
	    Tajima\'s D and Fu and Li\'s D* neutrality tests. The results are summarized in a table with the following 
	    fifteen columns:
      
              Alignment_name
              no_seqs
              aln_len
              avg_perc_identity
              pars_info_sites
              consistency_idx
              homoplasy_idx
              segregating_sites
              singletons
              pi_per_gene
              pi_per_site
              theta_per_gene
              theta_per_site
              tajimas_D
              fu_and_li_D_star

        This allows the user to identify neutral markers with desirable properties for standard population genetic analyses.

   INVOCATION EXAMPLES:
     1. default on DNA sequences (uses IQ-TREE evaluating a subset of models specified in the detailed help)
          $progname -R 1 -t DNA
     2. thorough FastTree searching and molecular clock analysis on DNA sequences using 10 cores:
          $progname -R 1 -t DNA -A F -k 1.2 -m 0.7 -s 20 -l 12 -T high -K -M HKY -q 0.95 -n 10
     3. FastTree searching on a huge protein dataset for fast inspection
          $progname -R 1 -A F -t PROT -m 0.6 -k 1.0 -T lowest
     4. To run the pipeline on a remote server, we recommend using the nohup command upfront, as shown below:
        nohup $progname -R 1 -t DNA -S 'TNe,TVM,TVMe,GTR' -k 1.0 -m 0.75 -T high -N 5 &> /dev/null &
     5. Run in population-genetics mode (generates a table with descritive statistics for DNA-polymorphisms 
          and the results of diverse neutrality tests)
	  $progname -R 2 -t DNA

   NOTES
     1: run from within the directory holding core gene clusters generated by get_homologues.pl -e or
          compare_clusters.pl with -t no_genome_gbk files (core genome: all clusters with a single gene copy per genome)
     2: If you encounter any problems, please run the script with the -D -V flags added at the end of the command line,
          redirect STOUT to a file and send us the output, so that we can better diagnose the problem.
	  e.g. $progname -R 1 -t DNA -k 1.0 -m 0.7 -s 8 -l 10 -T high -K -D &> ERROR.log
      
USAGE

exit 0

}

#-----------------------------------------------------------------------------------------

function print_help()
{
   cat <<EoH
   $progname v.$VERSION OPTIONS:

   REQUIRED:
    -R <integer> RUNMODE
       1 select optimal markers for phylogenetics/phylogenomics (genomes from different species)
       2 select optimal markers for population genetics (genomes from the same species)
    -t <string> type of input sequences: DNA|PROT

   OPTIONAL:
     -h|--help flag, print this short help notes
     -H flag, print extensive Help and details about search modes and models
     -A <string> Algorithm for tree searching: <F|I> [FastTree|IQ-TREE]                            [default:$search_algorithm]
     -c <integer> NCBI codontable number (1-23) for pal2nal.pl to generate codon alignment         [default:$codontable]
     -C flag to print codontables
     -D <int [1|2|3] to print debugging messages of low, high (set -v) and very high (set -vx) 
             verbosity, respectively. Please use -D <1|2> if you encounter problems                [default: $DEBUG]
     -e <integer> select gene trees with at least (min. = $min_no_ext_branches) external branches  [default: $min_no_ext_branches]
     -f <string> GET_HOMOLOGUES cluster format <STD|EST>                                           [default: $cluster_format]
     -I|--IQT_threads <integer> threads/cores for IQTree2 searching                                [default: $IQT_threads]
     -k <real> kde stringency (0.7-1.6 are reasonable values; less is more stringent)              [default: $kde_stringency]
     -K flag to run molecular clock test on codon alignments                                       [default: $eval_clock]
     -l <integer> max. spr length (7-12 are reasonable values)                                     [default: $spr_length]
     -m <real> min. average support value (0.6-0.8 are reasonable values) for trees to be selected [default: $min_supp_val]
     -M <string> base Model for clock test (use one of: GTR|TrN|HKY|K2P|F81); uses +G in all cases [default: $base_mod]
     -n <integer> number of cores/threads to use for parallel computations except IQT searches     [default: all cores]
     -N <integer> number of IQ-TREE searches to run [only active with -T high]                     [default: $nrep_IQT_searches]
     -q <real> quantile (0.95|0.99) of Chi-square distribution for computing molec. clock p-value  [default: $q]
     -r <string> root method (midpoint|outgroup)                                                   [default: $root_method]
     -s <integer> number of spr rounds (4-20 are reasonable values) for FastTree tree searching    [default: $spr]
     -S <string> quoted 'comma-separated list' of base models to be evaluated by IQ-TREE 
           when estimating the species tree from the concatenated supermatrix (see -H for details). 
	   If no -S is passed, then sinlge default models are used, as shown below
           <'JC,F81,K2P,HKY,TrN,TNe,K3P,K81u,TPM2,TPM2u,TPM3,TPM3u,
	     TIM,TIMe,TIM2,TIM2e,TIM3,TIM3e,TVM,TVMe,SYM,GTR'> for DNA alignments	           [default: $IQT_DNA_models]
           <'BLOSUM62,cpREV,Dayhoff,DCMut,FLU,HIVb,HIVw,JTT,JTTDCMut,LG,
             mtART,mtMAM,mtREV,mtZOA,Poisson,PMB,rtREV,VT,WAG'> for PROT alignments	           [default: $IQT_PROT_models]
     -T <string> tree search Thoroughness: high|medium|low|lowest (see -H for details)             [default: $search_thoroughness]
     -v|--version flag, print version and exit
     -V|--Versions flag, print software versions


   INVOCATION EXAMPLES:
     1. default on DNA sequences (uses IQ-TREE evaluating a subset of models specified in the detailed help)
          $progname -R 1 -t DNA -I 4
     2. thorough FastTree searching and molecular clock analysis on DNA sequences using 10 cores:
          $progname -R 1 -t DNA -A F -k 1.2 -m 0.7 -s 20 -l 12 -T high -K -M HKY -q 0.95 -n 10
     3. FastTree searching on a huge protein dataset for fast inspection
          $progname -R 1 -A F -t PROT -m 0.6 -k 1.0 -T lowest
     4. To run the pipeline on a remote server, we recommend using the nohup command upfront, as shown below:
        nohup $progname -R 1 -t DNA -S 'TNe,TVM,TVMe,GTR' -k 1.0 -m 0.75 -T high -N 5 -I 8 &> /dev/null &
     5. Run in population-genetics mode (generates a table with descritive statistics for DNA-polymorphisms 
          and the results of diverse neutrality test)
	      $progname -R 2 -t DNA

   NOTES
     1: run from within the directory holding core gene clusters generated by get_homologues.pl -e or
          compare_clusters.pl with -t no_genome_gbk files (core genome: all clusters with a single gene copy per genome)
     2: If you encounter any problems, please run the script with the -D -V flags added at the end of the command line,
          redirect STOUT to a file and send us the output, so that we can better diagnose the problem.
	      e.g. $progname -R 1 -t DNA -k 1.0 -m 0.7 -s 8 -l 10 -T high -K -D &> ERROR.log

EoH

exit 0

}
#-----------------------------------------------------------------------------------------

#------------------------------------#
#----------- GET OPTIONS ------------#
#------------------------------------#

# Required
runmode=0
mol_type=''

# Optional, with defaults
cluster_format=STD
search_thoroughness='high'
IQT_threads=2 # used only with concatenated supermatrix 2|INTEGER; AUTO is too slow
kde_stringency=1.5
min_supp_val=0.65
min_no_ext_branches=4
n_cores=''
#VERBOSITY=0
spr_length=8
spr=4
codontable=11 # bacterial by default, sorry for the bias ;)
base_mod=GTR
eval_clock=0
root_method=midpoint
tree_prefix=concat
q=0.99

search_algorithm=I
IQT_DNA_models=GTR
IQT_PROT_models=LG
IQT_models=''
nrep_IQT_searches=5

software_versions=0

declare -a args
args=("$@")

while getopts ':-:c:D:e:f:I:k:l:m:M:n:N:p:q:r:s:t:A:T:R:S:hCHKvV' VAL
do
   case $VAL in
   h)   print_help
        ;;
   A)   search_algorithm=$OPTARG
        ;;
   k)   kde_stringency=$OPTARG
        ;;
   c)   codontable=$OPTARG
        ;;
   C)	print_codontables
	;;
   D)   DEBUG=$OPTARG
        ;;
   e)   min_no_ext_branches=$OPTARG
        ;;
   f)   cluster_format=$OPTARG
        ;;
   H)   print_usage_notes
        ;;
   I)   IQT_threads=$OPTARG
        ;;
   K)   eval_clock=1
        ;;
   l)   spr_length=$OPTARG
        ;;
   m)   min_supp_val=$OPTARG
        ;;
   M)   base_mod=$OPTARG
        ;;
   n)   n_cores=$OPTARG
        ;;
   N)   nrep_IQT_searches=$OPTARG
        ;;
   p)   tree_prefix=$OPTARG
        ;;
   q)   q=$OPTARG
        ;;
   R)   runmode=$OPTARG
        ;;
   r)   root_method=$OPTARG
        ;;
   s)   spr=$OPTARG
        ;;
   S)   IQT_models=$OPTARG
        ;;
   t)   mol_type=$OPTARG
        ;;
   T)   search_thoroughness=$OPTARG
        ;;
   v)   echo "$progname v$VERSION" && exit 0
        ;;
   V)   software_versions=1
        ;;
#----------- add support for parsing long argument names-----------------------
   - ) 
        case $OPTARG in
        h* ) print_help ;;
	    v* ) { echo "$progname v$VERSION" && exit 0 ; } ;;
	    V* ) software_versions=1 ;;
          *    ) echo "# ERROR: invalid long options --$OPTARG" && print_help ;;
        esac >&2   # print the ERROR MESSAGES to STDERR
  ;;  
#------------------------------------------------------------------------------	 
   :)   printf "argument missing from -%s option\n" "-$OPTARG" 
   	print_help
     	;;
   *)   echo "invalid option: -$OPTARG" 
        echo
        print_help
	;;
   esac >&2   # print the ERROR MESSAGES to STDERR
done

shift $((OPTIND - 1))


#-------------------------------------------------------#
# >>>BLOCK 0.1 SET THE ENVIRONMENT FOR THE PIPELINE <<< #
#-------------------------------------------------------#

# logdir=$(pwd) # set on top of script

# 0. Set the distribution base directory and OS-specific (linux|darwin) bindirs
env_vars=$(set_pipeline_environment) # returns: $distrodir $bindir $OS $no_proc
(( DEBUG > 0 )) && echo "env_vars:$env_vars"
distrodir=$(echo "$env_vars"|awk '{print $1}')
bindir=$(echo "$env_vars"|awk '{print $2}')
OS=$(echo "$env_vars"|awk '{print $3}')
no_proc=$(echo "$env_vars"|awk '{print $4}')

# source get_phylomarkers_fun_lib into the script to get access to reminder of the functions
source "${distrodir}"/lib/get_phylomarkers_fun_lib || { echo "ERROR: could not source ${distrodir}/lib/get_phylomarkers_fun_lib" && exit 1 ; }

if (( DEBUG == 2 )); then
    # Print shell input lines as they are read. 
    set -v
elif (( DEBUG == 3 )); then # hysteric DEBUG level 
    # Print shell input lines as they are read.
    set -v
   
    # Print a trace of simple commands, for commands, case commands, select commands, and arithmetic for commands
    #  and their arguments or associated word lists after they are expanded and before they are executed. 
    set -x
fi

# check check_bash_version >= min_bash_version
check_bash_version

#-----------------------------------------------------------------------------------------

(( DEBUG > 0 )) && msg "distrodir:$distrodir|bindir:$bindir|OS:$OS|no_proc:$no_proc" DEBUG LBLUE

# 0.1 Determine if pipeline scripts are in $PATH;
# if not, add symlinks from ~/bin, if available
check_scripts_in_path "$distrodir" "$USER" || { msg "ERROR: check_scripts_in_path" ERROR RED && exit 1; }

# 0.2  Determine the bindir and add prepend it to PATH and export
set_bindirs "$bindir"

# 0.3 append the $distrodir/lib/R to R_LIBS and export
# NOTE: set -o nounset complained with the code below line 739: R_LIBS: unbound variable
#if [[ -n "$R_LIBS" ]]; then  
#    export R_LIBS="$R_LIBS:$distrodir/lib/R"
#else 
#    export R_LIBS="$distrodir/lib/R"
#fi
export R_LIBS="$distrodir/lib/R"  


# 0.4 append the $distrodir/lib/perl to PERL5LIB and export
export PERL5LIB="${distrodir}/lib/perl:${distrodir}/lib/perl/bioperl-1.5.2_102"

# 0.5 check all dependencies are in place
check_dependencies 1

(( software_versions == 1 )) && print_software_versions


#--------------------------------------#
# >>> BLOCK 0.2 CHECK USER OPTIONS <<< #
#--------------------------------------#

# check for bare minimum dependencies: bash R perl awk cut grep sed sort uniq Rscript

if (( runmode < 1 )) || (( runmode > 2 ))
then
    msg "# ERROR: need to define a runmode <int> [1|2]!" HELP RED
    print_help
fi

if [ "$search_algorithm" != "I" ] && [ "$search_algorithm" != "F" ]
then
    msg "# ERROR: search_algorithm $search_algorithm is not recognized!" ERROR RED
    print_help
fi

if (( min_no_ext_branches < 4 ))
then
    msg 'ERROR: -e has to be >= 4' HELP RED
    print_help
fi

if [ -z "$n_cores" ]
then
    n_cores="$no_proc"
fi

# make sure that the user does not request more cores than those available on host (default: AUTO)
((n_cores > no_proc)) && n_cores="$no_proc"
[[ "$IQT_threads" != 'AUTO' ]] && ((IQT_threads > no_proc)) && IQT_threads="$no_proc"

if [ "$mol_type" != "DNA" ] && [ "$mol_type" != "PROT" ] # "$mol_type" == "BOTH" not implemented yet
then
    msg "ERROR: -t must be DNA or PROT" ERROR RED
    print_help
fi

if [ -z "$IQT_models" ]
then
   [ "$mol_type" == "DNA" ] && IQT_models="$IQT_DNA_models"
   [ "$mol_type" == "PROT" ] && IQT_models="$IQT_PROT_models"
fi

if [ "$search_algorithm" == "I" ] && [ "$mol_type" == "DNA" ]
then
    check_IQT_DNA_models "$IQT_models"
fi

if [ "$search_algorithm" == "I" ] && [ "$mol_type" == "PROT" ]
then
    check_IQT_PROT_models "$IQT_models"
fi

if [ "$search_thoroughness" != "high" ] && [ "$search_thoroughness" != "medium" ] \
                                        && [ "$search_thoroughness" != "low" ] \
					                    && [ "$search_thoroughness" != "lowest" ]
then
    msg "ERROR: -T must be lowest|low|medium|high" HELP RED
    print_help
fi

if [ "$base_mod" != "GTR" ] && [ "$base_mod" != "TrN" ] && [ "$base_mod" != "HKY" ] \
                            && [ "$base_mod" != "K2P" ] && [ "$base_mod" != "F81" ]
then
    msg "ERROR: -M must be one of: GTR|TrN|HKY|K2P|F81" HELP RED
    print_help
fi

if (( eval_clock > 0 )) && [ "$mol_type" != "DNA" ] # MolClock currently only with DNA
then
    msg "-K 1 (evaluate clock) must be run on codon alignments with -t DNA" HELP RED
    print_help
fi

if (( runmode > 1 )) && [[ "$mol_type" != "DNA" ]] # PopGen analysis currently only with DNA
then
    msg "ERROR: runmode $runmode must be run on codon alignments with -t DNA" HELP RED
    print_help
fi

#---------------------#
# >>>> MAIN CODE <<<< #
#---------------------#

(( DEBUG > 0 )) && msg "running on $OSTYPE" DEBUG LBLUE && echo "path contains: " && echo -e "${PATH//:/'\n'}"

start_time=$(date +%s)

parent_PID=$(get_script_PID "$USER" "$progname")
(( DEBUG > 0 )) && msg "parent_PID:$parent_PID" DEBUG LBLUE

if (( eval_clock == 1 )) && [[ "$search_algorithm" == "F" ]]
then
    dir_suffix="A${search_algorithm}R${runmode}t${mol_type}_k${kde_stringency}_m${min_supp_val}_s${spr}_l${spr_length}_T${search_thoroughness}_K"
elif (( eval_clock != 1 )) && [[ "$search_algorithm" == "F" ]]
then
    dir_suffix="A${search_algorithm}R${runmode}t${mol_type}_k${kde_stringency}_m${min_supp_val}_s${spr}_l${spr_length}_T${search_thoroughness}"
elif (( eval_clock == 1 )) && [[ "$search_algorithm" == "I" ]]
then
    dir_suffix="A${search_algorithm}R${runmode}t${mol_type}_k${kde_stringency}_m${min_supp_val}_T${search_thoroughness}_K"
elif (( eval_clock != 1 )) && [ "$search_algorithm" == "I" ]
then
    dir_suffix="A${search_algorithm}R${runmode}t${mol_type}_k${kde_stringency}_m${min_supp_val}_T${search_thoroughness}"
fi

msg "$progname vers. $VERSION run with the following parameters:" PROGR CYAN

# <FIXME> # SC2124: $* Explicitly concatenates all the array elements into a single string <SOLVED>
lmsg=("Run started on $TIMESTAMP_SHORT_HMS under $OSTYPE on $HOSTNAME with $n_cores cores
 wkdir:$wkdir
 distrodir:$distrodir
 bindir:$bindir

 > General run settings:
      runmode:$runmode|mol_type:$mol_type|search_algorithm:$search_algorithm|cluster_format:$cluster_format
 > Filtering parameters:
     kde_stringency:$kde_stringency|min_supp_val:$min_supp_val
 > FastTree parameters:
     spr:$spr|spr_length:$spr_length|search_thoroughness:$search_thoroughness
 > IQ-TREE parameters:
     IQT_models:$IQT_models|search_thoroughness:$search_thoroughness
     nrep_IQT_searches:$nrep_IQT_searches|IQT_threads:$IQT_threads
 > Molecular Clock parmeters:
     eval_clock:$eval_clock|root_method:$root_method|base_model:$base_mod|ChiSq_quantile:$q
 > DEBUG=$DEBUG
 
 # script invocation: $progname ${args[@]}")

msg "${lmsg[*]}" PROGR YELLOW

#----------------------------------------------------------------------------------------------------------------
#>>>BLOCK 1. make a new subdirectory within the one holding core genome clusters generated by compare_clusters.pl
#    and generate symlinks to the faa and fna files (NOTE: BOTH REQUIRED). Fix fasta file names and headers.
#    Check that we have fna faa input FASTA file pairs and that they contain the same number of sequences and
#    instances of each taxon. Mark dir as top_dir
#----------------------------------------------------------------------------------------------------------------

if [ -d "get_phylomarkers_run_${dir_suffix}_${TIMESTAMP_SHORT}" ]
then
    msg "  >>> ERROR Found and older get_phylomarkers_run_${dir_suffix}_${TIMESTAMP_SHORT}/ directory. Please remove or rename and re-run!" ERROR RED
    exit 2
fi

msg "" PROGR NC
msg " >>>>>>>>>>>>>> running input data sanity checks <<<<<<<<<<<<<< " PROGR YELLOW
msg "" PROGR NC

# populate the alnIDs2names_h hash 
#  2332_hypothetical_protein_xzf.fna; key:2332 => val:2332_hypothetical_protein_xzf
while read -r a; do
    alnIDs2names["${a%%_*}"]="${a%.*}"
done < <(find . -maxdepth 1 -name "*.fna")

# make sure we have *.faa and *.fna file pairs to work on
if ! nfna=$(find . -maxdepth 1 -name "*.fna" | wc -l)
then
   msg " ERROR: there are no input fna files to work on!\n\tPlease check input FASTA files: [you may need to run compare_clusters.pl with -t NUM_OF_INPUT_GENOMES -n]\n\tPlease check the GET_HOMOLOGUES manual" ERROR RED
   msg "http://eead-csic-compbio.github.io/get_homologues/manual/" ERROR BLUE
   exit 2
fi

if ! nfaa=$(find . -maxdepth 1 -name "*.faa" | wc -l)
then
    msg "ERROR: there are no input faa files to work on!\n\tPlease check input FASTA files: [you may need to run compare_clusters.pl with -t NUM_OF_INPUT_GENOMES]\n\tPlease check the GET_HOMOLOGUES manual" ERROR RED
    msg "http://eead-csic-compbio.github.io/get_homologues/manual/" ERROR BLUE
    exit 2
fi

if (( nfna != nfaa ))
then
   lmsg=(" >>> ERROR: there are no equal numbers of fna and faa input files to work on!\n\tPlease check input FASTA files: [you may need to run compare_clusters.pl with -t NUM_OF_INPUT_GENOMES -n; and a second time: run compare_clusters.pl with -t NUM_OF_INPUT_GENOMES]")
   msg "${lmsg[*]}" ERROR RED
   msg "  Please check the GET_HOMOLOGUES manual at: " ERROR RED
   msg "  http://eead-csic-compbio.github.io/get_homologues/manual/" ERROR LBLUE
   exit 3
fi

filtering_results_h[starting_loci]="$nfna"
filtering_results_kyes_a+=('starting_loci')

{ mkdir "get_phylomarkers_run_${dir_suffix}_${TIMESTAMP_SHORT}" && cd "get_phylomarkers_run_${dir_suffix}_${TIMESTAMP_SHORT}" ; } \
 || { msg "ERROR: cannot cd into  get_phylomarkers_run_${dir_suffix}_${TIMESTAMP_SHORT}" ERROR RED && exit 1 ; }
top_dir=$(pwd)

print_start_time && msg "# processing source fastas in directory get_phylomarkers_run_${dir_suffix}_${TIMESTAMP_SHORT} ..." PROGR BLUE

ln -s ../*.faa .
ln -s ../*.fna .

# fix fasta file names with two and three dots
"$distrodir"/rename.pl 's/\.\.\./\./g' *.faa
"$distrodir"/rename.pl 's/\.\.\./\./g' *.fna

# make sure the fasta files do not contain characters that may interfere with the shell
"$distrodir"/rename.pl "s/\\'//g; s/\)//g; s/\,//g; s/\(//g; s/\[//g; s/\]//g; s#/##g; s/://g; s/\;//g" *.faa
"$distrodir"/rename.pl "s/\\'//g; s/\)//g; s/\,//g; s/\(//g; s/\[//g; s/\]//g; s#/##g; s/://g; s/\;//g" *.fna

# 1.0 check that all fasta files contain the same number of sequences
NSEQSFASTA=$(grep -c '^>' ./*.f[na]a | cut -d: -f 2 | sort | uniq | wc -l)
if (( NSEQSFASTA > 1 ))
then
    msg " >>> ERROR: Input FASTA files do not contain the same number of sequences..." ERROR RED
    grep -c '^>' ./*.f[na]a | cut -d: -f 2 | sort | uniq 
    exit 4
fi 

# 1.1 fix fastaheaders of the source protein and DNA fasta files
if [ "$cluster_format" == 'STD' ]; then
    # FASTA header format corresponds to GET_HOMOLOGUES
    for file in *faa; do 
        awk 'BEGIN {FS = "|"}{print $1, $2, $3}' "$file" |\
	    perl -pe 'if(/^>/){s/>\S+/>/; s/>\h+/>/; s/\h+/_/g; s/,//g; s/;//g; s/://g; s/\(//g; s/\)//g}' > "${file}"ed
    done
    for file in *fna; do 
        awk 'BEGIN {FS = "|"}{print $1, $2, $3}' "$file" |\
	    perl -pe 'if(/^>/){s/>\S+/>/; s/>\h+/>/; s/\h+/_/g; s/,//g; s/;//g; s/://g; s/\(//g; s/\)//g}' > "${file}ed"
    done
else
    # FASTA header format corresponds to GET_HOMOLOGUES_EST; keep first and last fields delimited by "|"
    for file in *faa; do 
        awk 'BEGIN {FS = " "}{print $1, $2}' "$file" |\
	    perl -pe 'if(/^>/){s/>\S+/>/; s/>\h+/>/; s/\h+/_/g; s/,//g; s/;//g; s/://g; s/\(//g; s/\)//g}' > "${file}"ed
    done
    for file in *fna; do
        awk 'BEGIN {FS = " "}{print $1, $2}' "$file" |\
	    perl -pe 'if(/^>/){s/>\S+/>/; s/>\h+/>/; s/\h+/_/g; s/,//g; s/;//g; s/://g; s/\(//g; s/\)//g}' > "${file}ed"
    done
fi

print_start_time && msg  "# Performing strain composition check on f?aed files ..." PROGR BLUE
faaed_strain_intersection_check=$(grep '>' ./*faaed | cut -d: -f2 | sort | uniq -c | awk '{print $1}' | sort | uniq -c | wc -l)
fnaed_strain_intersection_check=$(grep '>' ./*fnaed | cut -d: -f2 | sort | uniq -c | awk '{print $1}' | sort | uniq -c | wc -l)

# 1.2 check that each file has the same number of strains and a single instance for each strain
if (( faaed_strain_intersection_check == 1 )) && (( fnaed_strain_intersection_check == 1 ))
then
    msg " >>> Strain check OK: each f?aed file has the same number of strains and a single instance for each strain" PROGR GREEN
else
    grep '>' ./*faaed | cut -d: -f2 | sort | uniq -c | awk '{print $1}' | sort | uniq -c | wc -l
    grep '>' ./*faaed | cut -d: -f2 | sort | uniq -c
    grep '>' ./*fnaed | cut -d: -f2 | sort | uniq -c | awk '{print $1}' | sort | uniq -c | wc -l
    grep '>' ./*fnaed | cut -d: -f2 | sort | uniq -c
   
    msg " >>> ERROR: Input f?aed files do not contain the same number of strains and a single instance for each strain...
        Please check input FASTA files as follows: 
        1. Revise the output above to make sure that all genomes have a strain assignation and the same number of associated sequences. 
        If not, add strain name manually to the corresponding fasta files or exclude them.
        2. Make sure that only one genome/gbk file is provided for each strain.     
        3. You may need to run get_homologues.pl with -e or compare_clusters.pl with -t NUM_OF_INPUT_GENOMES to get clusters of equal sizes
        Please check the GET_HOMOLOGUES manual" ERROR RED
    msg "http://eead-csic-compbio.github.io/get_homologues/manual" ERROR BLUE
    exit 1
fi

# 1.3 add_nos2fasta_header.pl to avoid problems with duplicate labels
(( DEBUG > 0 )) && msg " > ${distrodir}/run_parallel_cmmds.pl faaed 'add_nos2fasta_header.pl \$file > \${file}no' $n_cores &> /dev/null" DEBUG NC
{ "${distrodir}"/run_parallel_cmmds.pl faaed 'add_nos2fasta_header.pl $file > ${file}no' "$n_cores" &> /dev/null && return 0; }

(( DEBUG > 0 )) && msg " > ${distrodir}/run_parallel_cmmds.pl fnaed 'add_nos2fasta_header.pl \$file > \${file}no' $n_cores &> /dev/null" DEBUG NC
{ "${distrodir}"/run_parallel_cmmds.pl fnaed 'add_nos2fasta_header.pl $file > ${file}no' "$n_cores" &> /dev/null && return 0; }

no_alns=$(find . -name "*.fnaedno" | wc -l)

filtering_results_h[num_alignments]="$no_alns"
filtering_results_kyes_a+=('num_alignments')

(( no_alns == 0 )) && msg " >>> ERROR: There are no codon alignments to work on! Something went wrong. Please check input and settings ... " ERROR RED && exit 4
print_start_time && msg "# Total number of alignments to be computed $no_alns" PROGR BLUE

# 1.3 generate a tree_labels.list file for later tree labeling
print_start_time && msg "# generating the labels file for tree-labeling ..." PROGR BLUE

tree_labels_dir=$(pwd)
if grep '>' "$(find . -name "*fnaedno" | head -1)" > /dev/null; then
    grep '>' "$(find . -name "*fnaedno" | head -1)" > tree_labels.list
else
   msg "ERROR in LINENO:$LINENO" ERROR RED && exit 1
fi

# NOTE: complains about unbound variable c
(( DEBUG > 0 )) && msg " > perl -pe '\$c++; s/>/\$c\t/; s/\h\[/_[/\\' tree_labels.list > k && mv k tree_labels.list" DEBUG NC
perl -pe '$c++; s/>/$c\t/; s/\h\[/_[/' tree_labels.list > k && mv k tree_labels.list


#------------------------------------------------------------------------------------------------------#
# >>>BLOCK 2. Generate cdnAlns with with pal2nal, maintaining the input-order of the source fastas <<< #
#------------------------------------------------------------------------------------------------------#

# 2.1 generate the protein alignments using clustalo
msg "" PROGR NC
msg " >>>>>>>>>>>>>>> parallel clustalo and pal2nal runs to generate protein and codon alignments <<<<<<<<<<<<<<< " PROGR YELLOW
msg "" PROGR NC

print_start_time &&  msg "# generating $no_alns protein alignments ..." PROGR BLUE
(( DEBUG > 0 )) \
  && msg " > '\${distrodir}/run_parallel_cmmds.pl faaedno clustalo -i \$file -o \${file%.*}_cluo.faaln --output-order input-order' \$n_cores &> /dev/null" DEBUG NC
{ "${distrodir}"/run_parallel_cmmds.pl faaedno 'clustalo -i $file -o ${file%.*}_cluo.faaln --output-order input-order' "$n_cores" &> clustalo.log && return 0 ; }

if grep -q "Thread creation failed" clustalo.log; then
   msg " >>> ERROR: This system cannot launch too many threads, please use option -n and re-run ..." ERROR RED
fi

# 2.2 generate the codon alignments (files with *_cdnAln.fasta extension) using pal2nal.pl,
#     excluding gaps, and mismatched codons, assuming a bacterial genetic code
# NOTE: to execute run_parallel_cmmds.pl with a customized command, resulting from the interpolation of multiple varialbles,
#       we have to first construct the command line in a variable and pipe its content into bash for executio

print_start_time && msg "# running pal2nal to generate codon alignments ..." PROGR LBLUE
faaln_ext=faaln
command="${distrodir}/run_parallel_cmmds.pl $faaln_ext '${distrodir}/pal2nal.pl \$file \${file%_cluo.faaln}.fnaedno -output fasta -nogap -nomismatch -codontable $codontable > \${file%_cluo.faaln}_cdnAln.fasta' $n_cores"

# now we can execute run_parallel_cmmds.pl with a customized command, resulting from the interpolation of multiple varialbles
(( DEBUG == 1 )) && msg " > \$command | bash &> /dev/null" DEBUG NC
{ echo "$command" | bash &> /dev/null && return 0 ; }

if ! ls ./*cdnAln.fasta > /dev/null; then
    msg "ERROR in $LINENO: could not find *cdnAln.fasta files" ERROR RED
fi

# check we got non-empty *cdnAln.fasta files
for f in ./*cdnAln.fasta
do
    if [[ ! -s "$f" ]]
    then
        msg " >>> Warning: produced empty codon alignment ${f}!" WARNING LRED
	    msg "    ... Will skip this locus and move it to problematic_alignments ..." WARNING LRED
	    [[ ! -d problematic_alignments ]] && mkdir problematic_alignments
	    locus_base=${f%_cdnAln.fasta}
	    mv "$f" problematic_alignments
	    mv "${locus_base}"* problematic_alignments
    else
	continue
    fi
done

# 2.3 cleanup: remove the source faa, fna, fnaed and faaed files; make numbered_fna_files.tgz and numbered_faa_files.tgz; rm *aedno
rm ./*fnaed ./*faaed ./*faa ./*fna
(( DEBUG > 0 )) && msg " > tar -czf numbered_fna_files.tgz ./*fnaedno" DEBUG NC
tar -czf numbered_fna_files.tgz ./*fnaedno
(( DEBUG > 0 )) && msg " > tar -czf numbered_fna_files.tgz ./*faaedno" DEBUG NC
tar -czf numbered_faa_files.tgz ./*faaedno
rm ./*aedno

#-------------------------------------------------------------------------------#
# >>>BLOCK 2.1 Run the maximal matched-pairs tests to asses SRH assumptions <<< #
#-------------------------------------------------------------------------------#
# 2.4 This block runs the maximal matched-pairs tests of homogeneity to asses the SRH model violations.
# SRH = Stationarity, Reversibility, and Homogeneity assumptions made by standard substitutio models
# The test is implemented in IQ-Tree, as published by Naser-Khdour et al. (2019) in GBE 11(12)3341-3352.

msg "" PROGR NC
msg " >>>>>>>>>>>>>>> parallel SRHtest runs to identify alignments violating the maximal matched-pairs tests of homogeneity <<<<<<<<<<<<<<< " PROGR YELLOW
msg "" PROGR NC

# 2.4.1 check that we have codon alignments before proceeding
no_fasta_files=$(find . -name "*.fasta" | wc -l)
(( no_fasta_files < 1 )) && print_start_time && msg " >>> ERROR: there are no codon alignments to run SRHtests on. Will exit now!" ERROR RED && exit 1

# 2.4.2 run SRHtest in parallel, as implemented in IQ-TREE 
print_start_time && msg "# running SRHtests on $no_fasta_files codon alignments ..." PROGR LBLUE

# uses only n_cores/2 for the parallel run, to let each IQT call use 2 cores
half_ncores=$(echo "$n_cores / 2" | bc -l)
half_ncores="${half_ncores%.*}"

(( DEBUG > 0 )) && msg " > ${distrodir}/run_parallel_cmmds.pl fasta 'iqtree -s \$file --symtest-only --quiet -nt 2' $half_ncores &> /dev/null" DEBUG NC
{ "${distrodir}"/run_parallel_cmmds.pl fasta 'iqtree -s \$file --symtest-only --quiet -nt 2' "$half_ncores" && return 0 ; } # <FIXME>
#"${distrodir}"/run_parallel_cmmds.pl fasta 'iqtree -s \$file --symtest-only --quiet -nt 2' "$half_ncores" || \
#{ msg "ERROR: run_parallel_cmmds.pl fasta 'iqtree -s \$file --symtest-only --quiet -nt 2' $half_ncores did not run successfully" ERROR RED && exit 1 ; }

# verify that the SRHtest run successfully by collecting and counting the logfiles generated by IQT in the SRHtest_logs array 
#  and comparing that number with the no_fasta_files

# fill array SRHtest_logs with readarray
declare -a SRHtest_logs=()
# SRHtest_logs=( $(ls *.fasta) ) # <<< should be avoided
# NOTE: prefer readarray (mapfile) or read -a to split command output (or quote to avoid splitting).
readarray -t SRHtest_logs < <(find . -maxdepth 1 -type f -name "*.fasta" -printf '%f\n') # -printf '%f\n' avoids ./ prefix preceding files

if [[ "${#SRHtest_logs[@]}" -eq "$no_fasta_files" ]]
then
    msg " >>> The SRHtest run successfully on all $no_fasta_files codon alignments" PROGR GREEN
elif [[ "${#SRHtest_logs[@]}" -lt "$no_fasta_files" ]] && [[ "${#SRHtest_logs[@]}" -gt 0 ]]
then
    msg " >>> WARNING: The SRHtest run successfully only on ${#SRHtest_logs[@]} codon alignments" WARNING LRED
elif [[ "${#SRHtest_logs[@]}" -eq "$no_fasta_files" ]] && [[ "${#SRHtest_logs[@]}" -eq 0 ]]
then
    msg " >>> ERROR: The SRHtest failed to run successfully" ERROR RED && exit 1
fi

# 2.4.3 parse the SRHtests results tables
if [[ "${#SRHtest_logs[@]}" -gt  0 ]]; then
    parse_SRH_tests 'csv'

    output_files_a+=(SRHtests_tsv)
    output_files_h[SRHtests_tsv]=$(echo -e "$top_dir\tparsed_SRHtests.tsv") # ${top_dir##*/}
fi

filtering_results_h[n_alns_failing_SRHtests]="$no_alns_failing_SRHtests"
filtering_results_kyes_a+=('n_alns_failing_SRHtests')

filtering_results_h[n_alns_passing_SRHtests]="$no_alns_passing_SRHtests"
filtering_results_kyes_a+=('n_alns_passing_SRHtests')

#---------------------------------------------------------------------------------------------------------#
#>>>BLOCK 3. run Phi-test to identify recombinant codon alignments on all *_cdnAln.fasta source files <<< #
#---------------------------------------------------------------------------------------------------------#
# 3.1 make a new PhiPack subdirectory to work in. generate symlinks to ../*fasta files
#     Mark dir as phipack_dir
mkdir PhiPack || { msg "ERROR: cannot mkdir PhiPack ..." ERROR RED && exit 1 ; }
cd PhiPack || { msg "ERROR: cannot cd into PhiPack ..." ERROR RED && exit 1 ; }
wkdir=$(pwd)

ln -s ../*fasta .

# 3.1.2 check that we have codon alignments before proceeding
no_fasta_files=$(find . -name "*.fasta" | wc -l)

(( no_fasta_files < 1 )) && print_start_time && msg " >>> ERROR: there are no codon alignments to run Phi on. Will exit now!" ERROR RED && exit 4

msg "" PROGR NC
msg " >>>>>>>>>>>>>>> parallel phi(w) runs to identify alignments with recombinant sequences <<<<<<<<<<<<<<< " PROGR YELLOW
msg "" PROGR NC

# 3.2 run Phi from the PhiPack in parallel
print_start_time && msg "# running Phi recombination test in PhiPack dir ..." PROGR LBLUE
{ (( DEBUG > 0 )) && msg " > ${distrodir}/run_parallel_cmmds.pl fasta 'Phi -f $file -p 1000 > ${file%.*}_Phi.log' $n_cores &> /dev/null" DEBUG NC ; } || msg "WARNING in $LINENO" WARNING LRED

# NOTE: here Phi can exit with ERROR: Too few informative sites to test significance. Try decreasing windowsize or increasing alignment length
#   which breaks set -e
{ "${distrodir}"/run_parallel_cmmds.pl fasta 'Phi -f $file -p 1000 > ${file%.*}_Phi.log' "$n_cores" &> /dev/null && return 0 ; }

# 3.3 process the *_Phi.log files generated by Phi to write a summary table and print short overview to STDOUT
declare -a nonInfoAln=()
COUNTERNOINFO=0

[ -s Phi.log ] && rm Phi.log

set +e
for f in ./*_Phi.log
do
    if grep '^Too few' "$f" &> /dev/null # if exit status is not 0
    then
       # if there are "Too few informative sites"; assign dummy, non significative values
       # and report this in the logfile!
       (( COUNTERNOINFO++ ))
       norm=1
       perm=1
       echo -e "$f\t$norm\t$perm\tTOO_FEW_INFORMATIVE_SITES"
       nonInfoAln[COUNTERNOINFO]="$f"
    else
       perm=$(grep Permut "$f" | awk '{print $3}')
       norm=$(grep Normal "$f" | awk '{print $3}')

       [ "$perm" == "--" ] && perm=1
       [ "$norm" == "--" ] && norm=1
       #nonInfoAln[$COUNTERNOINFO]=""
       echo -e "$f\t$norm\t$perm"
    fi
done > Phi_results_"${TIMESTAMP_SHORT}".tsv

check_output Phi_results_"${TIMESTAMP_SHORT}".tsv "$parent_PID"

ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$wkdir")
output_files_a+=(Phi_recombination_test)
output_files_h[Phi_recombination_test]=$(echo -e "$ed_dir\tPhi_results_${TIMESTAMP_SHORT}.tsv")

no_non_recomb_alns_perm_test=$(awk '$2 > 5e-02 && $3 > 5e-02' Phi_results_"${TIMESTAMP_SHORT}".tsv | wc -l)
total_no_cdn_alns=$(find . -name '*_cdnAln.fasta' | wc -l)


# 3.4 Check the number of remaining non-recombinant alignments
if [ "${#nonInfoAln[@]}" == 0 ]
then
   lmsg=(" >>> Phi test result: there are $no_non_recomb_alns_perm_test non-recombinant alignments out of $total_no_cdn_alns input alignments")
   print_start_time && msg "${lmsg[*}}" PROGR GREEN
fi

if (( "${#nonInfoAln[@]}" > 0 ))
then
    lmsg=(" >>> Phi test WARNING: there ${#nonInfoAln[@]} alignments with too few informative sites for the Phi test to work on ... ")
    print_start_time && msg "${lmsg[*]}" WARNING LRED
   
    # print the names of the alignments with too few informative sites for the Phi test to be work on
    if (( DEBUG == 1 ))
    then
        msg " >>> The alignments with too few informative sites for the Phi test to be work on are:" WARNING LRED
        for f in "${nonInfoAln[@]}"
        do
             msg " >>> ${f}" WARNING LRED
        done
    fi
fi

(( no_non_recomb_alns_perm_test < 1 )) && print_start_time && msg " >>> ERROR: All alignments seem to have recombinant sequences. will exit now!" ERROR RED && exit 3

filtering_results_h[n_recomb_alns_perm_test]=$((total_no_cdn_alns - no_non_recomb_alns_perm_test))
filtering_results_kyes_a+=('n_recomb_alns_perm_test')

filtering_results_h[Phi_test_n_nonInfoAln]="${#nonInfoAln[@]}"
filtering_results_kyes_a+=('Phi_test_n_nonInfoAln')

filtering_results_h[n_non_recomb_alns_perm_test]="$no_non_recomb_alns_perm_test"
filtering_results_kyes_a+=('n_non_recomb_alns_perm_test')
(( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done

msg " >>> Phi test found ${filtering_results_h[n_recomb_alns_perm_test]} recombinant alignments" PROGR GREEN


#3.5 cleanup dir
tar -czf Phi_test_log_files.tgz ./*Phi.log
[ -s Phi_test_log_files.tgz ] && rm ./*Phi.log Phi.inf*
set -e

# 3.5.1 mv non-recombinant codon alignments and protein alignments to their own directories:
#     non_recomb_cdn_alns/ and  non_recomb_cdn_alns/
#     Mark dir as non_recomb_cdn_alns
mkdir non_recomb_cdn_alns || { msg "ERROR: could not mkdir non_recomb_cdn_alns" ERROR RED; exit 1 ; }
while IFS= read -r base
do
    cp "${base}".fasta non_recomb_cdn_alns
done < <(awk '$2 > 5e-02 && $3 > 5e-02{print $1}' Phi_results_"${TIMESTAMP_SHORT}".tsv |sed 's/_Phi\.log//')

mkdir non_recomb_FAA_alns || { msg "ERROR: could not mkdir non_recomb_FAA_alns" ERROR RED; exit 1 ; }
while IFS= read -r base
do
    cp ../"${base}"*.faaln non_recomb_FAA_alns
done < <(awk '$2 > 5e-02 && $3 > 5e-02{print $1}' Phi_results_"${TIMESTAMP_SHORT}".tsv | sed 's/_cdnAln_Phi\.log//')

# 3.5.2 cleanup phipack_dir; rm *fasta, which are the same as in topdir
rm ./*cdnAln.fasta


#=====================================
# >>>  Block 4. -t DNA RUNMODES   <<< 
#=====================================
#
#  NOTES:
#   * cd into non_recomb_cdn_alns and run FastTree|IQ-TREE in parallel on all codon alignments.
#   * For FastTree -T controls desired search thoroughness      (see details with -H)
#   * For IQT -T controls the number of models to be evaluated  (see details with -H)
# 
# 	 1. The conditionals below divide the flow into two large if blocks to run -t DNA|PROT
# 		    [ "$mol_type" == "DNA" ]
# 		    [ "$mol_type" == "PROT" ]
#   BLOCK 4 will work on DNA, either in phylogenetics (-R 1) or population genetics (-R 2 runmodes)
#   BLOCK 5 works on protein sequences in -R 1 exclusively


#:::::::::::::::::::::::::::
# >>> Filter gene trees <<< 
#:::::::::::::::::::::::::::
if [ "$mol_type" == "DNA" ]
then
    cd non_recomb_cdn_alns || { msg "ERROR: cannot cd into non_recomb_cdn_alns" ERROR RED && exit 1 ; }
    non_recomb_cdn_alns_dir=$(pwd)

    print_start_time && msg "# working in dir $non_recomb_cdn_alns_dir ..." PROGR LBLUE

    # 4.1 >>> call functions estimate_IQT_gene_trees | estimate_FT_gene_trees
    if [ "$search_algorithm" == "F" ]
    then
	msg "" PROGR NC
	msg " >>>>>>>>>>>>>>> parallel FastTree runs to estimate gene trees <<<<<<<<<<<<<<< " PROGR YELLOW
	msg "" PROGR NC

        print_start_time && msg "# estimating $no_non_recomb_alns_perm_test gene trees from non-recombinant sequences ..." PROGR LBLUE

        gene_tree_ext="ph"
	lmsg=(" > running estimate_FT_gene_trees $mol_type $search_thoroughness ...")
        (( DEBUG > 0 )) && msg "${lmsg[*]}" DEBUG NC
	
	estimate_FT_gene_trees "$mol_type" "$search_thoroughness" "$n_cores" "$spr" "$spr_length" "$bindir"
	
	# 4.1.1 check that FT computed the expected gene trees
        no_gene_trees=$(find . -name "*.ph" | wc -l)
        
	# set a trap (see SC2064 for correct quoting)
        trap 'cleanup_trap "$(pwd)" PHYLO_GENETREES' ABRT EXIT HUP QUIT TERM

	(( no_gene_trees < 1 )) && print_start_time && msg " >>> ERROR: There are no gene tree to work on in non_recomb_cdn_alns/. will exit now!" ERROR RED && exit 3

	# 4.1.2 generate computation-time and lnL stats
	(( DEBUG > 0 )) && msg "compute_FT_gene_tree_stats $mol_type $search_thoroughness" DEBUG NC
	compute_FT_gene_tree_stats "$mol_type" "$search_thoroughness" "$parent_PID"
	print_start_time && msg "# running compute_MJRC_tree ph $search_algorithm ..." PROGR BLUE
	compute_MJRC_tree ph "$search_algorithm" 
	
	filtering_results_h[n_starting_gene_trees]="$no_gene_trees"
        filtering_results_kyes_a+=('n_starting_gene_trees')
        (( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done
    else
        gene_tree_ext="treefile"
	msg "" PROGR NC
	msg " >>>>>>>>>>>>>>> parallel IQ-TREE runs to estimate gene trees <<<<<<<<<<<<<<< " PROGR YELLOW
	msg "" PROGR NC
	estimate_IQT_gene_trees "$mol_type" "$search_thoroughness" # "$IQT_models"
		
	# 4.1.1 check that IQT computed the expected gene trees
	no_gene_trees=$(find . -name "*.treefile" | wc -l)

        # set a trap (see SC2064 for correct quoting)
        trap 'cleanup_trap "$(pwd)" PHYLO_GENETREES' ABRT EXIT HUP QUIT TERM
	
	(( no_gene_trees < 1 )) && print_start_time && msg " >>> ERROR: There are no gene tree to work on in non_recomb_cdn_alns/. will exit now!" ERROR RED && exit 3

	# 4.1.2 generate computation-time, lnL and best-model stats
	compute_IQT_gene_tree_stats "$mol_type" "$search_thoroughness"      
	print_start_time && msg "# running compute_MJRC_tree treefile $search_algorithm ..." PROGR BLUE
	compute_MJRC_tree treefile "$search_algorithm" 
	
	filtering_results_h[n_starting_gene_trees]="$no_gene_trees"
        filtering_results_kyes_a+=('n_starting_gene_trees')
        (( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done

	# 4.1.3 Populate the aln_models_h hash and aln_models_a array from *stats.tsv generated by compute_IQT_gene_tree_stats
	gene_tree_stats_file=$(find . -name \*stats.tsv -printf '%f\n')
	
        ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$non_recomb_cdn_alns_dir")
        output_files_a+=(gene_tree_stats_file)
        output_files_h[gene_tree_stats_file]=$(echo -e "$ed_dir\t$gene_tree_stats_file")

	print_start_time && msg "# populating the aln_models_h hash from $gene_tree_stats_file ..." PROGR BLUE

        while read -r aln _  _ _ model _; do
            aln="${aln/.\//}"
            aln="${aln%.log}" 
            aln_models_a+=("${aln/.\//}")
            aln_models_h["${aln/.\//}"]="$model"
        done < <(awk 'NR > 1' "$gene_tree_stats_file");
    
       ((DEBUG > 1)) && { echo "# DEBUGGING aln_models_h ..."; for a in "${aln_models_a[@]}"; do echo -e "$a\t${aln_models_h[$a]}"; done ; }
    fi

    #remove trees with < 4 external branches
    print_start_time && msg "# counting branches on $no_non_recomb_alns_perm_test gene trees ..." PROGR BLUE
    (( DEBUG > 0 )) && msg " > count_tree_branches $gene_tree_ext no_tree_branches.list &> /dev/null" DEBUG NC
    (( DEBUG > 0 )) && msg " search_thoroughness: ${search_thoroughness}" DEBUG NC

    count_tree_branches "$gene_tree_ext" no_tree_branches.list &> /dev/null # || { msg "ERROR in count_tree_branches $gene_tree_ext no_tree_branches.list" ERROR RED && exit 1 ; }
    [ ! -s no_tree_branches.list ] && install_Rlibs_msg no_tree_branches.list ape
    
    check_output no_tree_branches.list "$parent_PID"
    # remove trees with < 5 external branches (leaves)
    (( DEBUG > 0 )) && msg " >  removing trees with < $min_no_ext_branches external branches (leaves)" DEBUG NC
     
    ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$non_recomb_cdn_alns_dir")
    output_files_a+=(n_branches_per_tree)
    output_files_h[n_branches_per_tree]=$(echo -e "$ed_dir\tno_tree_branches.list")
      
    # Collect the fasta file names producing "no real trees" with < 4 external branches in the no_tree_counter array
    #   and remove trivial trees and alignments
    declare -a no_tree_counter_a
    no_tree_counter_a=()

    while read -r phy; do
  	if [ "$search_algorithm" == "F" ]; then
            base=${phy//_FTGTR\.ph/}
        elif [ "$search_algorithm" == "I" ]; then
            base=${phy//\.treefile/}
        else
            continue  # Skip processing if search_algorithm is not "F" or "I"
        fi
	
        print_start_time && msg " will remove ${base} because it has < $min_no_ext_branches external branches" WARNING LRED
        if [ -s "$base" ]; then
	   (( DEBUG > 0 )) && msg "will remove: ${base} ..." DEBUG NC
	   no_tree_counter_a+=("$base")
	   rm "$base" "${base}".*
	fi	 
    done < <(grep -v '^#Tree' no_tree_branches.list | awk -v min_no_ext_branches="$min_no_ext_branches" 'BEGIN{FS="\t"; OFS="\t"}$7 < min_no_ext_branches {print $1}')
    
    if [[ "${#no_tree_counter_a[@]}" -gt 0 ]]; then
        msg " >>> WARNING: there are ${#no_tree_counter_a[@]} trees with < 1 internal branches (not real trees) that will be discarded ..." WARNING LRED
    fi
    
    filtering_results_h[n_trivial_gene_trees]="${#no_tree_counter_a[@]}"
    filtering_results_kyes_a+=('n_trivial_gene_trees')

    filtering_results_h[n_non_trivial_gene_trees]=$((no_gene_trees - "${#no_tree_counter_a[@]}"))
    filtering_results_kyes_a+=('n_non_trivial_gene_trees')
    (( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done
    
    msg "" PROGR NC
    msg " >>>>>>>>>>>>>>> filter gene trees for outliers with kdetrees test <<<<<<<<<<<<<<< " PROGR YELLOW
    msg "" PROGR NC

    if [ "$search_algorithm" == "F" ]
    then
        # 4.1 generate the all_GTRG_trees.tre holding all source trees, which is required by kdetrees
        #     Make a check for the existence of the file to interrupt the pipeline if something has gone wrong
        (( DEBUG > 0 )) && msg " > cat ./*.ph > all_gene_trees.tre" DEBUG NC
	(( DEBUG > 0 )) && msg " search_thoroughness: ${search_thoroughness}" DEBUG NC
        cat ./*.ph > all_gene_trees.tre
        check_output all_gene_trees.tre "$parent_PID"
        [ ! -s all_gene_trees.tre ] && exit 3
    else
        # 4.1 generate the all_IQT_trees.tre holding all source trees, which is required by kdetrees
        #     Make a check for the existence of the file to interrupt the pipeline if something has gone wrong
        (( DEBUG > 0 )) && msg " > cat ./*.treefile > all_gene_trees.tre" DEBUG NC
	(( DEBUG > 0 )) && msg " search_thoroughness:$search_thoroughness" DEBUG NC
	cat ./*.treefile > all_gene_trees.tre
        check_output all_gene_trees.tre "$parent_PID"
        [ ! -s all_gene_trees.tre ] && exit 3
    fi
    
    ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$non_recomb_cdn_alns_dir")
    output_files_a+=(all_source_gene_trees)
    output_files_h[all_source_gene_trees]=$(echo -e "$ed_dir\tall_gene_trees.tre")
    
    # 4.2 run_kdetrees.R at desired stringency
    print_start_time && msg "# running kde test ..." PROGR BLUE
    (( DEBUG > 0 )) && msg " > ${distrodir}/run_kdetrees.R ${gene_tree_ext} all_gene_trees.tre $kde_stringency &> /dev/null" DEBUG NC
    "${distrodir}"/run_kdetrees.R "${gene_tree_ext}" all_gene_trees.tre "$kde_stringency" &> /dev/null && { echo "run_kdetrees.R returns $?" ; } ### <FIXME>; instead of || \ next line
     #{ msg "WARNING could not run ${distrodir}/run_kdetrees.R ${gene_tree_ext} all_gene_trees.tre $kde_stringency &> /dev/null" WARNING LRED ; }
   
    # Print a warning if kdetrees could not be run, but do not exit
    if [ ! -s kde_stats_all_gene_trees.tre.out ]
    then
        PRINT_KDE_ERR_MESSAGE=1
        msg "# WARNING: could not write kde_stats_all_gene_trees.tre.out; check that kdetrees and ape are propperly installed ..." WARNING LRED
        msg "# WARNING:      will arbitrarily set no_kde_outliers to 0, i.e. NO kde filtering applied to this run!" WARNING LRED
        msg "# This issue can be easily avoided by running the containerized version available from https://hub.docker.com/r/vinuesa/get_phylomarkers!" PROGR GREEN
    fi
	
    # Check how many outliers were detected by kdetrees
    if [ ! -s kde_dfr_file_all_gene_trees.tre.tab ]
    then
        no_kde_outliers=0
        no_kde_ok=$(wc -l all_gene_trees.tre | awk '{print $1}')
    else
        # 4.3 mv outliers to kde_outliers
        check_output kde_dfr_file_all_gene_trees.tre.tab "$parent_PID"
	no_kde_outliers=$(grep -c outlier kde_dfr_file_all_gene_trees.tre.tab)
        no_kde_ok=$(grep -v outlier kde_dfr_file_all_gene_trees.tre.tab|grep -vc '^file')
    fi 
    ((DEBUG > 0 )) && msg "PRINT_KDE_ERR_MESSAGE: $PRINT_KDE_ERR_MESSAGE; no_kde_outliers:$no_kde_outliers; no_kde_ok:$no_kde_ok" DEBUG NC

    filtering_results_h[n_KDE_gene_tree_outliers]="$no_kde_outliers"
    filtering_results_kyes_a+=('n_KDE_gene_tree_outliers')

    filtering_results_h[n_KDE_gene_trees_OK]="$no_kde_ok"
    filtering_results_kyes_a+=('n_KDE_gene_trees_OK')
    (( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done


    # 4.4 Check how many cdnAlns passed the test and separate into two subirectories those passing and failing the test
    if (( no_kde_outliers > 0 ))
    then
        print_start_time && msg "# making dir kde_outliers/ and moving $no_kde_outliers outlier files into it ..." PROGR BLUE
        mkdir kde_outliers || { msg "ERROR: could not run mkdir kde_outliers" ERROR RED && exit 1 ; }
        if [ "$search_algorithm" == "F" ]; then
	   while read -r f; do
	       base=${f/_cdnAln*/_cdnAln} 
	       mv "${base}"* kde_outliers
	   done < <(grep outlier kde_dfr_file_all_gene_trees.tre.tab | cut -f1)
	fi  

	if [ "$search_algorithm" == "I" ]; then
	   while read -r f; do
	       mv "${f}"* kde_outliers
	   done < <(grep outlier kde_dfr_file_all_gene_trees.tre.tab | cut -f1|sed 's/\.treefile//')
	fi   
    else
        print_start_time && msg " >>> there are no kde-test outliers ..." PROGR GREEN
    fi

    if (( no_kde_ok > 0 ))
    then
        print_start_time && msg "# making dir kde_ok/ and linking $no_kde_ok selected files into it ..." PROGR BLUE
        mkdir kde_ok || { msg "ERROR: mkdir kde_ok failed" ERROR RED && exit 1 ; }
        cd kde_ok || { msg "ERROR: cannot cd into kde_ok" ERROR RED && exit 1 ; }
        ln -s ../*.${gene_tree_ext} .
        
	print_start_time && msg "# labeling $no_kde_ok gene trees in dir kde_ok/ ..." PROGR BLUE
        (( DEBUG > 0 )) && msg " > ${distrodir}/run_parallel_cmmds.pl ${gene_tree_ext} 'add_labels2tree.pl ../../../tree_labels.list $file' $n_cores &> /dev/null" DEBUG NC
	{ "${distrodir}"/run_parallel_cmmds.pl "${gene_tree_ext}" 'add_labels2tree.pl ../../../tree_labels.list $file' "$n_cores" &> /dev/null && return 0 ; }
        
	# remove symbolic links to cleanup kde_ok/
	find . -type l -delete
        cd ..
    else
         PRINT_KDE_ERR_MESSAGE=1
    fi
   
    ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$non_recomb_cdn_alns_dir")
    output_files_a+=(kdetrees_tests_on_all_gene_trees)
    output_files_h[kdetrees_tests_on_all_gene_trees]=$(echo -e "$ed_dir\tkde_dfr_file_all_gene_trees.tre.tab")
    
    read_svg_figs_into_hash "$ed_dir" figs_a figs_h
#----------------------------------------#
# >>> BLOCK 4.2: PHYLOGENETICS - DNA <<< #
#----------------------------------------#
    if (( runmode == 1 ))
    then
        # >>> 5.1 Compute likelihood mapping (only for IQ-Tree only) and average bipartition support values for each gene tree
	#         and write them to sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab
        wkdir=$(pwd)

        msg "" PROGR NC
        msg " >>>>>>>>>>>>>>> filter gene trees by phylogenetic signal content <<<<<<<<<<<<<<< " PROGR YELLOW
        msg "" PROGR NC

	print_start_time && msg "# computing tree support values and RF-distances ..." PROGR BLUE
        (( DEBUG > 0 )) && msg " > compute_suppValStas_and_RF-dist.R $wkdir 1 fasta ${gene_tree_ext} 1 &> /dev/null" DEBUG NC
        compute_suppValStas_and_RF-dist.R "$wkdir" 1 fasta "${gene_tree_ext}" 1 &> /dev/null

        print_start_time && msg "# writing summary tables ..." PROGR BLUE
        min_supp_val_perc="${min_supp_val#0.}"
        no_digits="${#min_supp_val_perc}"
        (( no_digits == 1 )) && min_supp_val_perc="${min_supp_val_perc}0"

	# NOTE: IQ-TREE -alrt 1000 provides support values in 1-100 scale, not as 0-1 as FT!
	#	therefore we convert IQT-bases SH-alrt values to 0-1 scale for consistency
	[ "$search_algorithm" == "I" ] && min_supp_val=$(echo "$min_supp_val * 100" | bc)

        awk -v min_supp_val="$min_supp_val" '$2 >= min_supp_val' sorted_aggregated_support_values4loci.tab > "sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab"
        check_output "sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab" "$parent_PID"
        
	ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$wkdir")
	output_files_a+=(sorted_aggregated_support_values_top_DNA_markers)
	output_files_h[sorted_aggregated_support_values_top_DNA_markers]=$(echo -e "$ed_dir\tsorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab")
	
        no_top_markers=$(perl -lne 'END{print $.}' "sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab")
        top_markers_dir="top_${no_top_markers}_markers_ge${min_supp_val_perc}perc"
	top_markers_tab=$(find . -maxdepth 1 -type f -name "sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab" -printf '%f\n')

        filtering_results_kyes_a+=('n_gene_trees_with_low_median_support')
        filtering_results_h[n_gene_trees_with_low_median_support]=$((no_kde_ok - no_top_markers))

        filtering_results_kyes_a+=('top_markers_median_supp_val')	
        filtering_results_h[top_markers_median_supp_val]="$no_top_markers"
        (( DEBUG > 1 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done	

       
        # Run likelihood mapping, only if algorithm == I (IQ-TREE)
	#    to asses tree-likeness and phylogenetic signal
        if [ "$search_algorithm" == "I" ]
        then
	    print_start_time && msg "# computing likelihood mappings to asses tree-likeness and phylogenetic signal ..." PROGR BLUE
            
	    # Run IQ-TREE -lmap and populate the aln_lmappings_a array and aln_lmappings_h hash
	    #  the aln_models_a array and aln_models_h were populated from *stats.tsv, after running compute_IQT_gene_tree_stats
	    for a in "${aln_models_a[@]}"; do
                if [ -s "$a" ]; then
	            ((DEBUG > 1)) && echo "iqtree -s $a -m ${aln_models_h[$a]} -te ${a}.treefile -lmap $lmap_sampling -T $n_cores --prefix lmapping_test_${a%.*} --quiet"
	            iqtree -s "$a" -m "${aln_models_h[$a]}" -te "${a}".treefile -lmap "$lmap_sampling" -T "$n_cores" --prefix lmapping_test_"${a%.*}" --quiet
        
	            # parse AU test results from iqtree files
	            aln_lmappings_a+=("$a")
	            aln_lmappings_h["$a"]=$(grep 'Number of fully resolved' lmapping_test_"${a%.*}".iqtree | sed 's/Number of fully.*=//; s/%)//')
                else
                    continue
                fi
            done 

            print_start_time && msg "# parsing likelihood mapping results, and writing summary table ..." PROGR BLUE
	    # Print the likelihood mapping results of each gene tree to a tsv file
	    for a in "${aln_lmappings_a[@]}"; do
                echo -e "$a\t${aln_lmappings_h[$a]}"
            done > geneTree_lmapping_tests.tsv

	    check_output geneTree_lmapping_tests.tsv "$parent_PID"
	    ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$wkdir")
	    output_files_a+=(geneTree_lmapping_tests)
	    output_files_h[geneTree_lmapping_tests]=$(echo -e "$ed_dir\tgeneTree_lmapping_tests.tsv")

            # cleanup the lmappint_test_files
	    [ -s geneTree_lmapping_tests.tsv ] && rm lmapping_test_* 
	    
	    # filter  lmapping results >= \$min_support_val_perc
            print_start_time && msg "# parsing likelihood mapping results table to identify trees with >= $min_supp_val_perc fully resolved quartets ..." PROGR BLUE
            awk -v min="$min_supp_val_perc" 'BEGIN{FS=OFS="\t"}$2 >= min' geneTree_lmapping_tests.tsv > \
	      geneTrees_passing_lmapping_tests_ge_"${min_supp_val_perc}".tsv
	    
	    check_output geneTrees_passing_lmapping_tests_ge_"${min_supp_val_perc}".tsv "$parent_PID"
	    ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$wkdir")
	    output_files_a+=(geneTree_passing_lmapping_tests)
	    output_files_h[geneTree_passing_lmapping_tests]=$(echo -e "$ed_dir\tgeneTrees_passing_lmapping_tests_ge_${min_supp_val_perc}.tsv")
	    
	    n_lmapping_tests=$(wc -l < geneTree_lmapping_tests.tsv)
	    n_alns_passing_lmapping_tests=$(wc -l < geneTrees_passing_lmapping_tests_ge_"${min_supp_val_perc}".tsv)
            n_alns_failing_lmapping_tests=$((n_lmapping_tests - n_alns_passing_lmapping_tests))
	    
	    msg " >>> $n_alns_passing_lmapping_tests alignments passed the likelihood mapping test at >= ${min_supp_val_perc}% out of $n_lmapping_tests ... " PROGR GREEN

            filtering_results_kyes_a+=('n_alns_failing_lmapping_tests')	
            filtering_results_h[n_alns_failing_lmapping_tests]="$n_alns_failing_lmapping_tests"

            filtering_results_kyes_a+=('n_alns_passing_lmapping_tests')	
            filtering_results_h[n_alns_passing_lmapping_tests]="$n_alns_passing_lmapping_tests"


            # Filter alignments passing both the likelihood mapping (lmap) AND
	    #   the min. median bipartition support tests >= min_supp_val_perc
            # 1. filter by lmap
	    while read -r id; do 
	        [ -z "$id" ] && continue
	        [[ "$id" =~ [^0-9]+ ]] && continue
	        ((DEBUG > 1)) && msg "# filter by lmap: running: alns_passing_lmap_and_suppval_h[$id]++" DEBUG NC
	        alns_passing_lmap_and_suppval_h["$id"]=1
	    done < <(cut -d_ -f1 geneTrees_passing_lmapping_tests_ge_"${min_supp_val_perc}".tsv)
        
	    # 2. filter by min_supp_val
	    while read -r id; do 
	        [ -z "$id" ] && continue
		id=${id//\"/}
	        [[ "$id" =~ [^0-9]+ ]] && continue
	        ((DEBUG > 1)) && msg "# filter by min_supp_val: running: alns_passing_lmap_and_suppval_h[$id]++" DEBUG NC
	        ((alns_passing_lmap_and_suppval_h["$id"]++)) || alns_passing_lmap_and_suppval_h["$id"]=1  # requires this test if id is unbound
	    done < <(cut -f1 "$top_markers_tab") # sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab
	    
	    if ((DEBUG > 1)); then
	        for a in "${!alns_passing_lmap_and_suppval_h[@]}"; do
	            printf "%s\t%d\n" "$a" "${alns_passing_lmap_and_suppval_h[$a]}"
	        done
            fi
	    # 3. fill the array of alignments passing both phylogenetic signal content tests (i.e. "${alns_passing_lmap_and_suppval_h[$a]}" == 2)
	    mapfile -t alns_passing_lmap_and_suppval_a < <(for a in "${!alns_passing_lmap_and_suppval_h[@]}"; do (("${alns_passing_lmap_and_suppval_h[$a]}" == 2 )) && echo "${a}"; done)

	    # 4. Reset the top_markers_dir and no_top_markers when runnig both phylogenetic signal filters under -A I (IQ-TREE)
	    top_markers_dir=top_"${#alns_passing_lmap_and_suppval_a[@]}"_markers_ge"${min_supp_val_perc}"perc
	    no_top_markers="${#alns_passing_lmap_and_suppval_a[@]}"
	    
	    msg " >>> $no_top_markers alignments passed both the lmapping and median bipartition support tests at >= ${min_supp_val_perc}% out of $n_lmapping_tests ..." PROGR GREEN

            filtering_results_kyes_a+=('n_alns_passing_lmapping_and_bipart_support_tests')	
            filtering_results_h[n_alns_passing_lmapping_and_bipart_support_tests]="$no_top_markers"
	fi # [ "$search_algorithm" == "I" ]
	
	# >>> 5.2 move top-ranking markers to $top_markers_dir
	print_start_time && msg "# making dir $top_markers_dir and moving $no_top_markers top markers into it ..." PROGR LBLUE
        { mkdir "$top_markers_dir" && cd "$top_markers_dir" ; } || { msg "ERROR: cannot cd into $top_markers_dir" ERROR RED && exit 1 ; }
        top_markers_dir=$(pwd)
        
        if [ "$search_algorithm" == "F" ] # FastTree
        then
	    ln -s ../"$top_markers_tab" .
	    while read -r id _; do 
	         [[ "$id" =~ loci ]] && continue
	         id=${id//\"/}
	     
	         # -h doesn't work with globs. Use a for loop
	         while read -r i; do
	             (( DEBUG > 0 )) && msg " > reading top_markers_tab:$top_markers_tab in top_markers_dir:$top_markers_dir; running: ln -s ../${i} ." DEBUG NC
	             if [ ! -h "$i" ]
		     then
	                 ln -s ../"$i" .
	             else
	                 continue
	             fi
	         done < <(find .. -maxdepth 1 -name "${id}"\* -printf "%f\n")
	    done < "$top_markers_tab"
        else # IQ-Tree
	    for id in "${alns_passing_lmap_and_suppval_a[@]}"
	    do 
	        while read -r i
		do
	            (( DEBUG > 0 )) && msg " > reading top_markers_tab:$top_markers_tab in top_markers_dir:$top_markers_dir; running: ln -s ../${i} ." DEBUG NC
	            if [ ! -h "$i" ]
		    then
	        	ln -s ../"$i" .
	            else
	        	continue
	            fi
	        done < <(find .. -maxdepth 1 -name "${id}"\* -printf "%f\n")
            done
	fi

        # set a trap in case the script exits here (see SC2064 for correct quoting)
	trap 'cleanup_trap "$(pwd)" PHYLO_SIGNAL' ABRT EXIT HUP INT QUIT TERM
	(( no_top_markers < 2 )) && print_start_time && \
	msg " >>> WARNING: There are less than 2 top markers. Relax the filtering thresholds. Will exit now!" WARNING LRED && exit 3

        msg "" PROGR NC
        msg " >>>>>>>>>>>>>>> generate supermatrix from concatenated, top-ranking alignments <<<<<<<<<<<<<<< " PROGR YELLOW
        msg "" PROGR NC

        # >>> 5.3 generate supermatrix (concatenated alignment)
        print_start_time && msg "# concatenating $no_top_markers top markers into supermatrix ..." PROGR BLUE
        (( DEBUG > 0 )) && msg " > concat_alns fasta $parent_PID &> /dev/null" DEBUG NC
        
	concat_alns fasta "$parent_PID" &> /dev/null
	check_output concat_cdnAlns.fna "$parent_PID"
	ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$top_markers_dir")
	output_files_a+=(concat_cdnAlns_fna)
	output_files_h[concat_cdnAlns_fna]=$(echo -e "$ed_dir\tconcat_cdnAlns.fna")

        # >>> 5.4 remove uninformative sites from the concatenated alignment to speed up computation
        print_start_time && msg "# removing uninformative sites from concatenated alignment ..." PROGR BLUE
        (( DEBUG > 0 )) && msg " > ${distrodir}/remove_uninformative_sites_from_aln.pl < concat_cdnAlns.fna > concat_cdnAlns.fnainf" DEBUG NC
	"${distrodir}"/remove_uninformative_sites_from_aln.pl < concat_cdnAlns.fna > concat_cdnAlns.fnainf
        check_output concat_cdnAlns.fnainf "$parent_PID"
	
	output_files_a+=(concat_cdnAlns_fnainf)
	output_files_h[concat_cdnAlns_fnainf]=$(echo -e "$ed_dir\tconcat_cdnAlns.fnainf")
	
	read_svg_figs_into_hash "$ed_dir" figs_a figs_h

        # Set a trap in case the script exits here (see SC2064 for correct quoting)
	trap 'cleanup_trap "$(pwd)" PHYLO_SUPERMATRIX' ABRT EXIT HUP INT QUIT TERM
	[ ! -s concat_cdnAlns.fnainf ] && print_start_time && \
	msg " >>> ERROR: The expected file concat_cdnAlns.fnainf was not produced! Will exit now!" ERROR RED && exit 3

        #:::::::::::::::::::::::::::::::::::::#
        # >>> FastTree species tree - DNA <<< #
        #:::::::::::::::::::::::::::::::::::::#

	if [[ "$search_algorithm" == "F" ]]	
        then
	    
	    # ============== #
	    # >>> ASTRAL <<< #
	    # -------------- #
	    msg "" PROGR NC
	    msg " >>>>>>>>>>>>>>> Computing ASTRAL species tree on ${no_top_markers} top marker gene trees <<<<<<<<<<<<<<< " PROGR YELLOW
	    msg "" PROGR NC

	    print_start_time && msg "# running compute_MJRC_tree ph $search_algorithm ..." PROGR BLUE
	    compute_MJRC_tree ph "$search_algorithm" 
 
            # compute ASTRAL species tree on the alltrees.nwk file
            if [[ -s alltrees.nwk ]]
            then
	        ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$top_markers_dir")
		output_files_a+=(concatenated_top_markers_DNA_gene_trees)
	        output_files_h[concatenated_top_markers_DNA_gene_trees]=$(echo -e "$ed_dir\talltrees.nwk")
                print_start_time && msg "# computing ASTRAL species tree from ${no_top_markers} top marker gene trees ..." PROGR BLUE
                (( DEBUG > 0 )) && msg " > run_ASTRAL alltrees.nwk $no_top_markers $tree_labels_dir $n_cores" DEBUG NC
                run_ASTRAL alltrees.nwk "${no_top_markers}" "$tree_labels_dir" "$n_cores"
            else
                msg " >>> WARNING: file alltrees.nwk was not found; cannot run ASTRAL ..." WARNING LRED
            fi

            ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$top_markers_dir")
	    output_files_a+=(ASTRAL4_species_tree)
            output_files_h[ASTRAL4_species_tree]=$(echo -e "$ed_dir\tastral4_top${no_top_markers}geneTrees_ed.sptree")

            output_files_a+=(wASTRAL_species_tree)
            output_files_h[wASTRAL_species_tree]=$(echo -e "$ed_dir\twastral_top${no_top_markers}geneTrees_ed.sptree")

            output_files_a+=(wASTRAL_concord_stats)
            output_files_h[wASTRAL_concord_stats]=$(echo -e "$ed_dir\twastral_concord.cf.stat")

            output_files_a+=(IQTree_constrained_by_wASTRALspTree)
            output_files_h[IQTree_constrained_by_wASTRALspTree]=$(echo -e "$ed_dir\tIQTree_constrained_by_wASTRALspTree_ed.treefile")
    	    
	    msg "" PROGR NC
	    msg " >>>>>>>>>>>>>>> FastTree run on supermatrix to estimate the species tree <<<<<<<<<<<<<<< " PROGR YELLOW
	    msg "" PROGR NC

	    # 5.4 run FasTree under the GTR+G model
            print_start_time && msg "# running FastTree on the supermatrix with $search_thoroughness thoroughness. This may take a while ..." PROGR BLUE
	  
            (( DEBUG > 0 )) && msg " search_thoroughness: $search_thoroughness" DEBUG NC
	    if [[ "$search_thoroughness" == "high" ]]
            then
                "$bindir"/FastTree -quiet -nt -gtr -gamma -bionj -slow -slownni -mlacc 3 -spr "$spr" -sprlength "$spr_length" \
	          -log "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log < concat_cdnAlns.fnainf > \
	          "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph
            fi

            if [[ "$search_thoroughness" == "medium" ]]
            then
                "$bindir"/FastTree -quiet -nt -gtr -gamma -bionj -slownni -mlacc 2 -spr "$spr" -sprlength "$spr_length" \
	            -log "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log < concat_cdnAlns.fnainf > \
	            "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph
            fi

            if [[ "$search_thoroughness" == "low" ]]
            then
                { "$bindir"/FastTree -quiet -nt -gtr -gamma -bionj -spr "$spr" -sprlength "$spr_length" \
	            -log "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log < concat_cdnAlns.fnainf > \
	            "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph && return 0 ; }
            fi

            if [[ "$search_thoroughness" == "lowest" ]]
            then
                "$bindir"/FastTree -quiet -nt -gtr -gamma -mlnni 4 -log "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log \
	            < concat_cdnAlns.fnainf > "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph
            fi

            check_output "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph "$parent_PID"
	    output_files_a+=(Fast_tree_supermatix_tree)
	    output_files_h[Fast_tree_supermatix_tree]=$(echo -e "$ed_dir\t${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph")

	    if [[ -s "${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log" ]] && [[ -s "${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph" ]]
	    then
	    	lnL=$(awk '/^Gamma20LogLk/{print $2}' "${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log")
	    	msg " >>> lnL for ${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph = $lnL" PROGR GREEN
	    else
	    	msg " >>> ERROR: ${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log could not be produced, will stop here" ERROR LRED
	    	exit 5
	    fi

            print_start_time && msg "# Adding labels back to tree ..." PROGR BLUE

	    longmsg=" > ${distrodir}/add_labels2tree.pl ${tree_labels_dir}/tree_labels.list ${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph &> /dev/null"
            (( DEBUG > 0 )) && msg "$longmsg" DEBUG NC
            "${distrodir}"/add_labels2tree.pl "${tree_labels_dir}"/tree_labels.list "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph &> /dev/null

            if [[ -s "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG_ed.ph ]]
            then
	        # for compute_suppValStats_and_RF-dist.R
                mv "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG_ed.ph "${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}cdnAlns_FTGTRG_ed.sptree"
                check_output "${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}cdnAlns_FTGTRG_ed.sptree" "$parent_PID"
		output_files_a+=(Fast_tree_supermatix_tree_with_labels)
	        output_files_h[Fast_tree_supermatix_tree_with_labels]=$(echo -e "$ed_dir\t${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}cdnAlns_FTGTRG_ed.sptree")
                msg " >>> found in dir $top_markers_dir ..." PROGR GREEN
            else
                msg " >>> WARNING: ${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}cdnAlns_FTGTRG_ed.sptree could not be produced" WARNING LRED
            fi

            print_start_time && msg "# computing the mean support values and RF-distances of each gene tree to the concatenated tree ..." PROGR BLUE
	    (( DEBUG > 0 )) && msg " > compute_suppValStas_and_RF-dist.R $top_markers_dir 2 fasta ph 1 &> /dev/null" DEBUG NC
            "$distrodir"/compute_suppValStas_and_RF-dist.R "$top_markers_dir" 2 fasta ph 1 &> /dev/null || \
	    { msg "ERROR: could not excute $distrodir/compute_suppValStas_and_RF-dist.R $top_markers_dir 2 fasta ph 1" ERROR RED; exit 1 ; }
	  
	    # top100_median_support_values4loci.tab should probably not be written in the first instance
	    [[ -s top100_median_support_values4loci.tab ]] && (( no_top_markers < 101 )) && rm top100_median_support_values4loci.tab
	    
	     read_svg_figs_into_hash "$ed_dir" figs_a figs_h
	    
        fi # [ "$search_algorithm" == "F" ]

        #::::::::::::::::::::::::::::::::::::#
        # >>> IQ-TREE species tree - DNA <<< #
        #::::::::::::::::::::::::::::::::::::#
        if [[ "$search_algorithm" == "I" ]]
        then
            # ============== #
	    # >>> ASTRAL <<< #
	    # -------------- #

	    msg "" PROGR NC
	    msg " >>>>>>>>>>>>>>> Computing ASTRAL-IV and wASTRAL species trees from ${no_top_markers} top marker gene trees <<<<<<<<<<<<<<< " PROGR YELLOW
	    msg "" PROGR NC

            print_start_time && msg "# running compute_MJRC_tree treefile $search_algorithm ..." PROGR BLUE
	    (( DEBUG > 0 )) && msg "  >  compute_MJRC_tree treefile $search_algorithm" DEBUG NC
	    compute_MJRC_tree treefile "$search_algorithm" 
	    
            # compute ASTRAL-IV and wASTRAL species trees on the alltrees.nwk file
            if [ -s alltrees.nwk ]
            then
	        ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$top_markers_dir")
		output_files_a+=(concatenated_top_markers_DNA_gene_trees)
	        output_files_h[concatenated_top_markers_DNA_gene_trees]=$(echo -e "$ed_dir\talltrees.nwk")
                print_start_time && msg "# computing ASTRAL species tree from ${no_top_markers} top marker gene trees ..." PROGR BLUE
                (( DEBUG > 0 )) && msg "  > run_ASTRAL alltrees.nwk $no_top_markers $tree_labels_dir $n_cores" DEBUG NC
                run_ASTRAL alltrees.nwk "${no_top_markers}" "$tree_labels_dir" "$n_cores"
            else
                msg " >>> WARNING: file alltrees.nwk was not found; cannot run ASTRAL ..." WARNING LRED
            fi 
            
	    ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$top_markers_dir")
            output_files_a+=(ASTRAL4_species_tree)
            output_files_h[ASTRAL4_species_tree]=$(echo -e "$ed_dir\tastral4_top${no_top_markers}geneTrees_ed.sptree")

            output_files_a+=(wASTRAL_species_tree)
            output_files_h[wASTRAL_species_tree]=$(echo -e "$ed_dir\twastral_top${no_top_markers}geneTrees_ed.sptree")

            output_files_a+=(wASTRAL_concord_stats)
            output_files_h[wASTRAL_concord_stats]=$(echo -e "$ed_dir\twastral_concord.cf.stat")

            output_files_a+=(IQTree_constrained_by_wASTRALspTree)
            output_files_h[IQTree_constrained_by_wASTRALspTree]=$(echo -e "$ed_dir\tIQTree_constrained_by_wASTRALspTree_ed.treefile")

	    # 5.5 run IQ-tree in addition to FastTree, if requested
            msg "" PROGR NC
	    msg " >>>>>>>>>>>>>>> ModelFinder + IQ-TREE run on supermatrix to estimate the species tree <<<<<<<<<<<<<<< " PROGR YELLOW
	    msg "" PROGR NC
	    
	    print_start_time && msg "# running ModelFinder on the concatenated alignment with $IQT_models. This will take a while ..." PROGR BLUE

            "$bindir"/iqtree -s concat_cdnAlns.fnainf -st DNA -mset "$IQT_models" -m MF -T "$IQT_threads" -n 0 &> /dev/null

	    check_output concat_cdnAlns.fnainf.log "$parent_PID"
	    output_files_a+=(IQ-Tree_supermatix_logfile)
	    output_files_h[IQ-Tree_supermatix_logfile]=$(echo -e "$ed_dir\tconcat_cdnAlns.fnainf.log")

	    best_model=$(grep '^Best-fit model' concat_cdnAlns.fnainf.log | cut -d' ' -f 3)
	    msg " >>> Best-fit model: ${best_model} ..." PROGR GREEN

	    { mkdir iqtree_abayes && cd iqtree_abayes ; } || { msg "ERROR: cannot cd into iqtree_abayes" ERROR RED && exit 1 ; }
	    ln -s ../concat_cdnAlns.fnainf .

	    if [[ "$search_thoroughness" == "high" ]]
	    then
	    	lmsg=("# Will launch $nrep_IQT_searches IQ-TREE searches on the supermatrix with best model ${best_model} --abayes -B 1000!.
	    		  This will take a while ...")
	    	print_start_time && msg "${lmsg[*]}" PROGR BLUE

	    	# run nrep_IQT_searches IQ-TREE searches under the best-fit model found
	    	for ((rep=1;rep<=nrep_IQT_searches;rep++))
	    	do
	    	    print_start_time && msg " > iqtree -s concat_cdnAlns.fnainf -st DNA -m $best_model --abayes -B 1000 -T $IQT_threads --prefix abayes_run${rep} &> /dev/null" PROGR LBLUE
	    	    "$bindir"/iqtree -s concat_cdnAlns.fnainf -st DNA -m "$best_model" --abayes -B 1000 -T "$IQT_threads" --prefix abayes_run"${rep}" &> /dev/null
	    	done

	    	grep '^BEST SCORE' ./*log | sed 's#./##' | sort -nrk5 > sorted_IQ-TREE_searches.out

	    	check_output sorted_IQ-TREE_searches.out "$parent_PID"

	        output_files_a+=(sorted_IQ-TREE_searches)
	        output_files_h[sorted_IQ-TREE_searches]=$(echo -e "$ed_dir\tsorted_IQ-TREE_searches.out")

	    	best_search=$(head -1 sorted_IQ-TREE_searches.out)
	    	best_search_base_name=$(head -1 sorted_IQ-TREE_searches.out | cut -d\. -f 1)

	    	msg "# >>> Best IQ-TREE run was: $best_search ..." PROGR GREEN
	    	best_tree_file="${tree_prefix}_${best_search_base_name}_nonRecomb_KdeFilt_iqtree_${best_model}.treefile"
	        best_tree_file_ed="${tree_prefix}_${best_search_base_name}_nonRecomb_KdeFilt_iqtree_${best_model}_ed.sptree"

	    	# Note: this function works within iqtree_abayes/ and takes care of:
	    	# 1. labeling the species tree and moving it to top_markers_dir 
	    	# 2. making a cleanup in iqtree_abayes/
	    	# 3. moves to top_markers_dir to compute RF-dist of gene-trees to species-tree
	    	# 4. removes the double extension name *.fasta.treefile and changes treefile for ph to make it paup-compatible for clock-test
            	process_IQT_species_trees_for_molClock "$best_search_base_name" "$best_tree_file" "$top_markers_dir" "$no_top_markers"
              
		output_files_a+=(IQTree_concat_cdnAln_spTree)
                output_files_h[IQTree_concat_cdnAln_spTree]=$(echo -e "$ed_dir\t$best_tree_file_ed")
 	    else
	    	print_start_time && msg "# running IQ-tree on the concatenated alignment with best model ${best_model} --abayes -B 1000. This will take a while ..." PROGR BLUE

	    	"$bindir"/iqtree -s concat_cdnAlns.fnainf -st DNA -m "$best_model" --abayes -B 1000 -T "$IQT_threads" --prefix iqtree_abayes &> /dev/null

	    	grep '^BEST SCORE' ./*log | sed 's#./##' | sort -nrk5 > sorted_IQ-TREE_searches.out

	    	check_output sorted_IQ-TREE_searches.out "$parent_PID"

	        output_files_a+=(sorted_IQ-TREE_searches)
	        output_files_h[sorted_IQ-TREE_searches]=$(echo -e "$ed_dir\tsorted_IQ-TREE_searches.out")

	    	best_search=$(head -1 sorted_IQ-TREE_searches.out)
	    	best_search_base_name=$(head -1 sorted_IQ-TREE_searches.out | cut -d\. -f 1)

	    	msg "# >>> Best IQ-TREE run was: $best_search ..." PROGR GREEN
	    	best_tree_file="${tree_prefix}_nonRecomb_KdeFilt_iqtree_${best_model}.treefile"
		best_tree_file_ed="${tree_prefix}_nonRecomb_KdeFilt_iqtree_${best_model}_ed.sptree"
            	process_IQT_species_trees_for_molClock iqtree_abayes "$best_tree_file" "$top_markers_dir" "$no_top_markers"
		
		output_files_a+=(IQTree_concat_cdnAln_spTree)
                output_files_h[IQTree_concat_cdnAln_spTree]=$(echo -e "$ed_dir\t$best_tree_file_ed")
	    fi

            read_svg_figs_into_hash "$ed_dir" figs_a figs_h

        fi # if [ "$search_algorithm" == "I" ]
        
        # NOTE: after v0.9 this process is prallelized with run_parallel_cmmds.pl
	if (( eval_clock > 0 ))
        then
	    msg "" PROGR NC
	    msg " >>>>>>>>>>>>>>> TESTING THE MOLECULAR CLOCK HYPOTHESIS <<<<<<<<<<<<<<< " PROGR YELLOW
	    msg "" PROGR NC

 	    # 1. convert fasta2nexus
            print_start_time && msg "# converting fasta files to nexus files" PROGR BLUE
	    (( DEBUG > 0 )) && msg " > $distrodir/convert_aln_format_batch_bp.pl fasta fasta nexus nex &> /dev/null" DEBUG NC
            "$distrodir"/convert_aln_format_batch_bp.pl fasta fasta nexus nex &> /dev/null

	    # FIX the nexus file format produced by bioperl: (recent paup version error message provided below)
	    # User-defined symbol 'A' conflicts with predefined DNA state symbol.
            # If you are using a predefined format ('DNA', 'RNA', 'nucleotide', or 'protein'),
            # you may not specify predefined states for this format as symbols in  the Format command.
	    for nexusf in ./*.nex
	    do
		perl -pe 'if(/^format /){ s/symbols.*$/;/}' "$nexusf" > k && mv k "$nexusf"
	    done

	    print_start_time && msg "# Will test the molecular clock hypothesis for $no_top_markers top markers. This will take some time ..." PROGR BLUE
            #run_molecClock_test_jmodeltest2_paup.sh -R 1 -M $base_mod -t ph -e fasta -b molec_clock -q $q &> /dev/null

	    # 2. >>> print table header and append results to it
            no_dot_q=${q//\./}
            results_table="mol_clock_M${base_mod}G_r${root_method}_q${no_dot_q}_ClockTest.tab"
            echo -e "#nexfile\tlnL_unconstr\tlnL_clock\tLRT\tX2_crit_val\tdf\tp-val\tmol_clock" > "$results_table" 
	     
	    cmd="${distrodir}/run_parallel_cmmds.pl nex '${distrodir}/run_parallel_molecClock_test_with_paup.sh -R 1 -f \$file -M $base_mod -t ph -b global_mol_clock -q $q' $n_cores"
	    (( DEBUG > 0 )) && msg "run_parallel_molecClock.cmd: $cmd" DEBUG NC
	    { echo "$cmd" | bash &> /dev/null && return 0 ; }
           
	    mol_clock_tab=$(ls ./*_ClockTest.tab)

       	    if [[ -s "$mol_clock_tab" ]]
	    then
		msg " >>> generated the molecular clock results file $mol_clock_tab ..." PROGR GREEN

        	# Paste filoinfo and clocklikeness tables
        	cut -f1 gene_trees2_concat_tree_RF_distances.tab | grep -v loci | sed 's/"//; s/"$/_/' > list2grep.tmp
        	head -1 "$mol_clock_tab" > header.tmp

		# sort lines in molecular clock output file according to order in gene_trees2_concat_tree_RF_distances.tab
		while read -r line
		do
		    grep "$line" "$mol_clock_tab"
		done < list2grep.tmp >> "${mol_clock_tab}"sorted

		cat header.tmp "${mol_clock_tab}"sorted > k && mv k "${mol_clock_tab}"sorted

        	paste gene_trees2_concat_tree_RF_distances.tab "${mol_clock_tab}"sorted > phylogenetic_attributes_of_top"${no_top_markers}"_gene_trees.tab

		check_output phylogenetic_attributes_of_top"${no_top_markers}"_gene_trees.tab "$parent_PID"
		output_files_a+=(mol_clock_top_gene_trees_table)
	        output_files_h[mol_clock_top_gene_trees_table]=$(echo -e "$ed_dir\tphylogenetic_attributes_of_top${no_top_markers}_gene_trees.tab")
		
		msg " >>> Top markers and associated stats are found in: $ed_dir ..." PROGR GREEN
            else
		msg " >>> ${mol_clock_tab} not found" ERROR RED
	    fi
	    
	    read_svg_figs_into_hash "$ed_dir" figs_a figs_h

        fi # if [ $eval_clock -gt 0 ]

    #-------------------------
    # >>> 5.4 cleanup DNA <<< 
    #-------------------------
    # >>> from version >= v2.8.4.0_2024-04-20
    #	  cleanup is performed by trap calls to trap cleanup_trap

    fi # if (( runmode == 1 )); then run phylo pipeline on DNA seqs


    #----------------------------------------#
    # >>> BLOCK 4.3: POPULATION GENETICS <<< #
    #----------------------------------------#
    if (( runmode == 2 ))
    then
        msg "" PROGR NC
        msg " >>>>>>>>>>>>>>> run descriptive DNA polymorphism statistics and neutrality tests <<<<<<<<<<<<<<< " PROGR YELLOW
        msg "" PROGR NC

        { mkdir popGen && cd popGen ; } || { msg "ERROR: cannot cd into popGen" ERROR RED && exit 1 ; }
	popGen_dir=$(pwd)
        non_recomb_cdn_alns_dir="${popGen_dir%/*}" 
	  
        print_start_time && msg "# Moved into dir popGen ..." PROGR LBLUE

	ln -s ../*fasta .
    	no_top_markers=$(find . -name \*.fasta | wc -l)
    	tmpf=$(find . -maxdepth 1 -name \*.fasta | head -1)
    	if [ -s "$tmpf" ]
	then
	     no_seqs=$(grep -c '>' "$tmpf")
	fi
    	(( DEBUG > 0 )) && msg "no_seqs:$no_seqs" DEBUG NC
    
        print_start_time && msg "# Will run descriptive DNA polymorphism statistics for $no_top_markers top markers. This will take some time!" PROGR BLUE

	TajD_l=TajD_u=FuLi_lFuLi_u=''

    	declare -a TajD_crit_vals
	TajD_crit_vals=()
	#TajD_crit_vals=( $(get_critical_TajD_values "$no_seqs") ) 
	# key fix! read -a to split command output (SC2207) <FIXME> DONE
	read -r -a TajD_crit_vals <<< "$(get_critical_TajD_values "$no_seqs")"
    	TajD_l=${TajD_crit_vals[0]}
    	TajD_u=${TajD_crit_vals[1]}
    
    	declare -a FuLi_crit_vals
	FuLi_crit_vals=()
	#FuLi_crit_vals=( $(get_critical_FuLi_values "$no_seqs") )
	read -r -a FuLi_crit_vals <<< "$(get_critical_FuLi_values "$no_seqs")"
    	FuLi_l=${FuLi_crit_vals[0]}
    	FuLi_u=${FuLi_crit_vals[1]}
	
	lmsg=("# TajD_crit_vals:$TajD_crit_vals|TajD_l:$TajD_l|TajD_u:$TajD_u|FuLi_crit_vals:$FuLi_crit_vals|FuLi_l:$FuLi_l|FuLi_u:$FuLi_u")
    	msg "${lmsg[*]}" PROGR GREEN
    
        print_start_time && msg "# converting $no_top_markers fasta files to nexus format ..." PROGR BLUE
        (( DEBUG > 0 )) && msg " > convert_aln_format_batch_bp.pl fasta fasta nexus nex &> /dev/null" DEBUG NC
	convert_aln_format_batch_bp.pl fasta fasta nexus nex &> /dev/null
     
        print_start_time && msg "# Running popGen_summStats.pl ..." PROGR BLUE
    	lmsg=(" > $distrodir/popGen_summStats.pl -R 2 -n nex -f fasta -F fasta -H -r 100 -t $TajD_l -T $TajD_u -s $FuLi_l -S $FuLi_u &> popGen_summStats_hs100.log")
    	(( DEBUG > 0 )) && msg "${lmsg[*]}" PROGR GREEN
    	"$distrodir"/popGen_summStats.pl -R 2 -n nex -f fasta -F fasta -H -r 100 -t "$TajD_l" -T "$TajD_u" -s "$FuLi_l" -S "$FuLi_u" &> popGen_summStats_hs100.log
    
    	check_output polymorphism_descript_stats.tab "$parent_PID"
	
	ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$popGen_dir")
	output_files_a+=(polymorphism_descript_stats)
	output_files_h[polymorphism_descript_stats]=$(echo -e "$ed_dir\tpolymorphism_descript_stats.tab")
	
	# save the neutral loci into array (SC2207)
	declare -a neutral_loci
	neutral_loci=()
	while read -r aln; do 
	    neutral_loci+=("$aln")
	done < <(awk 'BEGIN{FS=OFS="\t"}NR > 1 && ! /\*/{print $1}' polymorphism_descript_stats.tab)
	
	msg " >>> Found ${#neutral_loci[@]} netural loci (Tajima's D and Fu & Li's D* tests) out of $no_top_markers top markers ..." PROGR GREEN
	msg " >>> descriptive DNA polymorphism stats are found in: $popGen_dir ..." PROGR GREEN
		
	filtering_results_h[n_non_neutral_markers]=$((no_top_markers - "${#neutral_loci[@]}"))
        filtering_results_kyes_a+=('n_non_neutral_markers')
	
	filtering_results_h[n_neutral_markers]="${#neutral_loci[@]}"
        filtering_results_kyes_a+=('n_neutral_markers')
        (( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done	

	# move Nexus and FASTA files for neutral loci into its own dir for further processeing 
	if ((${#neutral_loci[@]} > 0 ))
	then
	    mkdir neutral_loci_"${#neutral_loci[@]}" || { msg "ERROR: cannot mkdir neutral_loci_${#neutral_loci[@]}" ERROR RED && exit 1 ; }
	    print_start_time && msg " # moving into neutral_loci_${#neutral_loci[@]} ..." PROGR LBLUE
	    for f in "${neutral_loci[@]}"; do
	        base="${f%.fasta}"
	        mv "${base}"_clean.fasta neutral_loci_"${#neutral_loci[@]}"
            done
	else
	    msg "Will stop here: 0 neutral loci found in polymorphism_descript_stats.tab" WARNING LRED
	fi
	
	n_non_neutral_loci=$(find . -maxdepth 1 -name \*_clean.fasta | wc -l)
	if (( n_non_neutral_loci > 0 ))
	then
	    mkdir non_neutral_loci || { msg "ERROR: cannot mkdir non_neutral_loci" ERROR RED && exit 1 ; }
	
	    msg " >>> moving $n_non_neutral_loci non-neutral markers into non_neutral_loci/ ..." PROGR GREEN
	    mv ./*fasta non_neutral_loci
	    (("${#neutral_loci[@]}" > 0 )) && mv ./*.nex non_neutral_loci
	fi
	
	# Concatentate neutral loci, generate SNP matrix and compute phylogeny
	if (("${#neutral_loci[@]}" > 1 ))
	then
	    cd neutral_loci_"${#neutral_loci[@]}" || { msg "ERROR: cannot cd into neutral_loci_${#neutral_loci[@]}" ERROR RED && exit 1 ; }
	    
	    neutral_loci_dir=$(pwd)
 
            msg "" PROGR NC
            msg " >>>>>>>>>>>>>>> generate supermatrix from concatenated, top-ranking, neutral alignments <<<<<<<<<<<<<<< " PROGR YELLOW
            msg "" PROGR NC

            # >>> 5.3 generate supermatrix (concatenated alignment)
            print_start_time && msg "# concatenating ${#neutral_loci[@]} top, neutral markers into supermatrix ..." PROGR BLUE
            (( DEBUG > 0 )) && msg " > concat_alns fasta $parent_PID &> /dev/null" DEBUG NC
        
	    concat_alns fasta "$parent_PID" &> /dev/null
	    
	    check_output concat_cdnAlns.fna "$parent_PID"
	    output_files_a+=(concat_cdnAlns_neutral_markers)
	    output_files_h[concat_cdnAlns_neutral_markers]=$(echo -e "neutral_loci_${#neutral_loci[@]}\tconcat_cdnAlns.fna")
	            
            # >>> 5.4 Compute SNPs from the concatenated alignment using snp-sites https://github.com/sanger-pathogens/snp-sites
	    # NOTE: available on CONDA and installable from apt repo for Debian/Ubuntu 
            print_start_time && msg "# generating a SNPs matrix in FASTA format from the concatenated alignment ..." PROGR BLUE
        
	    # Generate the snp-matrix in FASTA format
	    "$bindir"/snp-sites-static -cm -o concat_cdnAlns_SNPs.fasta concat_cdnAlns.fna # activate only for statically-linked binary
	    #snp-sites -cm -o concat_cdnAlns_SNPs.fasta concat_cdnAlns.fna                 # for system-wide install, e.g. with apt install snp-sites
	    check_output concat_cdnAlns_SNPs.fasta "$parent_PID"

	    ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "neutral_loci_${#neutral_loci[@]}")
	    output_files_a+=(concat_cdnAlns_SNPs_fasta)
	    output_files_h[concat_cdnAlns_SNPs_fasta]=$(echo -e "$ed_dir\tconcat_cdnAlns_SNPs.fasta")

	    # Generate the snp-matrix in VCF format
	    "$bindir"/snp-sites-static -cv -o concat_cdnAlns_SNPs.vcf concat_cdnAlns.fna # activate only for statically-linked binary
	    #snp-sites -cv -o concat_cdnAlns_SNPs.vcf concat_cdnAlns.fna                 # for system-wide install, e.g. with apt install snp-sites
	    check_output concat_cdnAlns_SNPs.vcf "$parent_PID"
	    output_files_a+=(concat_cdnAlns_SNPs_vcf)
	    output_files_h[concat_cdnAlns_SNPs_vcf]=$(echo -e "$ed_dir\tconcat_cdnAlns_SNPs.vcf")
	    
            #:::::::::::::::::::::::::::::::::#
            # >>> FT-TREE Population tree <<< #
            #:::::::::::::::::::::::::::::::::#
            if [[ "$search_algorithm" == "F" ]]	
            then
	        msg "" PROGR NC
	        msg " >>>>>>>>>>>>>>> FastTree run on supermatrix to estimate the species tree <<<<<<<<<<<<<<< " PROGR YELLOW
	        msg "" PROGR NC

	        # 5.4 run FasTree under the GTR+G model
                print_start_time && msg "# running FastTree on the SNP supermatrix with $search_thoroughness thoroughness. This may take a while ..." PROGR BLUE
	  
                (( DEBUG > 0 )) && msg " search_thoroughness: $search_thoroughness" DEBUG NC
	        if [[ "$search_thoroughness" == "high" ]]
                then
                    "$bindir"/FastTree -quiet -nt -gtr -gamma -bionj -slow -slownni -mlacc 3 -spr "$spr" -sprlength "$spr_length" \
	              -log "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log < concat_cdnAlns_SNPs.fasta > \
	              "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph
                fi

                if [[ "$search_thoroughness" == "medium" ]]
                then
                    "$bindir"/FastTree -quiet -nt -gtr -gamma -bionj -slownni -mlacc 2 -spr "$spr" -sprlength "$spr_length" \
	            -log "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log < concat_cdnAlns_SNPs.fasta > \
	            "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph
                fi

                if [[ "$search_thoroughness" == "low" ]]
                then
                    { "$bindir"/FastTree -quiet -nt -gtr -gamma -bionj -spr "$spr" -sprlength "$spr_length" \
	            -log "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log < concat_cdnAlns_SNPs.fasta > \
	            "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph && return 0 ; }
                fi

                if [[ "$search_thoroughness" == "lowest" ]]
                then
                    "$bindir"/FastTree -quiet -nt -gtr -gamma -mlnni 4 -log "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log \
	            < concat_cdnAlns_SNPs.fasta > "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph
                fi

                check_output "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph "$parent_PID"


	        if [[ -s "${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log" ]] && [[ -s "${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph" ]]
	        then
	    	    lnL=$(awk '/^Gamma20LogLk/{print $2}' "${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log")
	    	    msg " >>> lnL for ${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph = $lnL" PROGR GREEN
	        else
	    	    msg " >>> ERROR: ${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.log could not be produced, will stop here" ERROR LRED
	    	    exit 5
	        fi

                print_start_time && msg "# Adding labels back to tree ..." PROGR BLUE

	        longmsg=" > ${distrodir}/add_labels2tree.pl ${tree_labels_dir}/tree_labels.list ${tree_prefix}_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph &> /dev/null"
                (( DEBUG > 0 )) && msg "$longmsg" DEBUG NC
                "${distrodir}"/add_labels2tree.pl "${tree_labels_dir}"/tree_labels.list "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG.ph &> /dev/null

                if [[ -s "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG_ed.ph ]]
                then
                    mv "${tree_prefix}"_nonRecomb_KdeFilt_cdnAlns_FTGTRG_ed.ph "${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}cdnAlns_FTGTRG_ed.poptree"
                    check_output "${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}cdnAlns_FTGTRG_ed.poptree" "$parent_PID"
		    output_files_a+=(FT_concat_cdnAln_SNPs_popTree)
	            output_files_h[FT_concat_cdnAln_SNPs_popTree]=$(echo -e "$ed_dir\t${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}cdnAlns_FTGTRG_ed.poptree")
                else
                    msg " >>> WARNING: ${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}cdnAlns_FTGTRG_ed.poptree could not be produced" WARNING LRED
                fi
            fi # [ "$search_algorithm" == "F" ]

            #:::::::::::::::::::::::::::::::::#
            # >>> IQ-TREE Population tree <<< #
            #:::::::::::::::::::::::::::::::::#
            if [[ "$search_algorithm" == "I" ]]
            then
	        if [[ "$search_thoroughness" == "high" ]]
	        then
	    	    lmsg=("# Searching for the best ML tree for the SNP supermatrix with 1000 IQ-Tree superfast boostrap replicates, this may take a while ...")
	    	    print_start_time && msg "${lmsg[*]}" PROGR BLUE

	    	    # run nrep_IQT_searches IQ-TREE searches under the best-fit model found
	    	    print_start_time && msg " >>> Running $bindir/iqtree -s concat_cdnAlns_SNPs.fasta -st DNA -B 1000 -T $IQT_threads &> /dev/null" PROGR LBLUE
	    	    "$bindir"/iqtree -s concat_cdnAlns_SNPs.fasta -st DNA -B 1000 -T "$IQT_threads" &> /dev/null
		        
	    	    check_output concat_cdnAlns_SNPs.fasta.treefile "$parent_PID"
                    best_fit_model=$(awk '/^Best-fit model:/{print $3}' concat_cdnAlns_SNPs.fasta.log)
		    
		    longmsg=" > ${distrodir}/add_labels2tree.pl ${tree_labels_dir}/tree_labels.list concat_cdnAlns_SNPs.fasta.treefile &> /dev/null"
                    (( DEBUG > 0 )) && msg "$longmsg" DEBUG NC
                    "${distrodir}"/add_labels2tree.pl "${tree_labels_dir}"/tree_labels.list concat_cdnAlns_SNPs.fasta.treefile &> /dev/null

		    if [ -s concat_cdnAlns_SNPs_ed.fasta ]
		    then 
		       mv concat_cdnAlns_SNPs_ed.fasta concat_cdnAlns_SNPs_population_tree.ph
		       check_output concat_cdnAlns_SNPs_population_tree.ph "$parent_PID"
	               output_files_a+=(IQT_concat_cdnAln_SNPs_popTree)
	               output_files_h[IQT_concat_cdnAln_SNPs_popTree]=$(echo -e "$ed_dir\tconcat_cdnAlns_SNPs_population_tree.ph")
		    else
		       msg "# WARGNING: could not produce the edited file concat_cdnAlns_SNPs_population_tree.ph" WARNING LRED
		    fi 
	        else
	    	    print_start_time && msg ">>> Running $bindir/iqtree -s concat_cdnAlns_SNPs.fasta -st DNA -mset K2P,HKY,TN,TIM,TVM,GTR -B 1000. This will take a while ..." PROGR BLUE
	    	    "$bindir"/iqtree -s concat_cdnAlns_SNPs.fasta -st DNA -mset K2P,HKY,TN,TIM,TVM,GTR -B 1000 -T "$IQT_threads" &> /dev/null
	    	    check_output concat_cdnAlns_SNPs.fasta.treefile "$parent_PID"
                    best_fit_model=$(awk '/^Best-fit model:/{print $3}' concat_cdnAlns_SNPs.fasta.log)
		    
		    msg ">>> Best-fit model selected by BIC for concat_cdnAlns_SNPs.fasta is: $best_fit_model" PROGR GREEN
		    
		    longmsg=" > ${distrodir}/add_labels2tree.pl ${tree_labels_dir}/tree_labels.list concat_cdnAlns_SNPs.fasta.treefile &> /dev/null"
                    (( DEBUG > 0 )) && msg "$longmsg" DEBUG NC
                    "${distrodir}"/add_labels2tree.pl "${tree_labels_dir}"/tree_labels.list concat_cdnAlns_SNPs.fasta.treefile &> /dev/null
		   
		    if [ -s concat_cdnAlns_SNPs_ed.fasta ]
		    then 
		       mv concat_cdnAlns_SNPs_ed.fasta concat_cdnAlns_SNPs_population_tree.ph
		       check_output concat_cdnAlns_SNPs_population_tree.ph "$parent_PID"
	               output_files_a+=(IQT_concat_cdnAln_SNPs_popTree)
	               output_files_h[IQT_concat_cdnAln_SNPs_popTree]=$(echo -e "$ed_dir\tconcat_cdnAlns_SNPs_population_tree.ph")
		    else
		       msg "# WARGNING: could not produce the edited file concat_cdnAlns_SNPs_population_tree.ph" WARNING LRED
		    fi 
	        fi
            fi # if [ "$search_algorithm" == "I" ] 
        
	    read_svg_figs_into_hash "$ed_dir" figs_a figs_h

	fi # if (("${#neutral_loci[@]}" > 1 ))
   
    	#>>> CLEANUP <<<#
        # >>> from version >= v2.8.4.0_2024-04-20
        #	  cleanup is performed by trap calls to trap cleanup_trap

    fi # if $runmode -eq 2   
fi # if [ "$mol_type" == "DNA"


#::::::::::::::::: END -t DNA RUNMODES ::::::::::::::::#

#======================================================#
# >>>  Block 5. -t PROTEIN GENE AND SPECIES TREES  <<< #
#======================================================#

if [[ "$mol_type" == "PROT" ]]
then
    cd non_recomb_FAA_alns || { msg "ERROR: cannot cd into non_recomb_FAA_alns" ERROR RED && exit 1 ; }
    non_recomb_FAA_alns_dir=$(pwd)

    print_start_time && msg "# working in dir $non_recomb_FAA_alns_dir ..." PROGR LBLUE
    print_start_time && msg "# estimating $no_non_recomb_alns_perm_test gene trees from non-recombinant sequences ..." PROGR LBLUE

    # 5.1 >>> estimate_IQT_gene_trees | estimate_FT_gene_trees
    if [[ "$search_algorithm" == "F" ]]
    then
    	msg "" PROGR NC
    	msg " >>>>>>>>>>>>>>> parallel FastTree runs to estimate gene trees <<<<<<<<<<<<<<< " PROGR YELLOW 
    	msg "" PROGR NC
    
        gene_tree_ext="ph"
    	lmsg=(" > running estimate_FT_gene_trees $mol_type $search_thoroughness ...")
        (( DEBUG > 0 )) && msg "${lmsg[*]}" DEBUG NC
    	estimate_FT_gene_trees "$mol_type" "$search_thoroughness" "$n_cores" "$spr" "$spr_length" "$bindir"
    
    	# 4.1.1 check that FT computed the expected gene trees
        no_gene_trees=$(find . -name "*.ph" | wc -l)

        # set a trap in case the script exits here (see SC2064 for correct quoting)
	trap 'cleanup_trap "$(pwd)" PHYLO_GENETREES' ABRT EXIT HUP INT QUIT TERM
        (( no_gene_trees < 1 )) && print_start_time && \
	msg " >>> WARNING: There are no gene tree to work on in non_recomb_cdn_alns/. Relax the filtering thresholds. Will exit now!" WARNING RED && exit 3
    
    	# 4.1.2 generate computation-time and lnL stats
    	compute_FT_gene_tree_stats "$mol_type" "$search_thoroughness" "$parent_PID"
    	
    	print_start_time && msg "# running compute_MJRC_tree $gene_tree_ext $search_algorithm ..." PROGR BLUE
    	compute_MJRC_tree "$gene_tree_ext" "$search_algorithm" 

	filtering_results_h[n_starting_gene_trees]="$no_gene_trees"
        filtering_results_kyes_a+=('n_starting_gene_trees')
        (( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done
    else
        gene_tree_ext="treefile"
    	msg "" PROGR NC
    	msg " >>>>>>>>>>>>>>> parallel IQ-TREE runs to estimate gene trees <<<<<<<<<<<<<<< " PROGR YELLOW
    	msg "" PROGR NC
    
    	estimate_IQT_gene_trees "$mol_type" "$search_thoroughness" # "$IQT_models"
    	
    	# 4.1.1 check that IQT computed the expected gene trees
    	no_gene_trees=$(find . -name '*.treefile' | wc -l)
        
	# set a trap in case the script exits here (see SC2064 for correct quoting)
        trap 'cleanup_trap "$(pwd)" PHYLO_GENETREES' ABRT EXIT HUP INT QUIT TERM       
	(( no_gene_trees < 1 )) && \
	print_start_time && \
	msg " >>> WARNING: There are no gene tree to work on in non_recomb_cdn_alns/. Relax the filter thresholds. Will exit now!" WARNING LRED && exit 3
    
    	# 4.1.2 generate computation-time, lnL and best-model stats
    	compute_IQT_gene_tree_stats "$mol_type" "$search_thoroughness"
    	
    	print_start_time && msg "# running compute_MJRC_tree $gene_tree_ext $search_algorithm ..." PROGR BLUE
        compute_MJRC_tree "$gene_tree_ext" "$search_algorithm" 

	filtering_results_h[n_starting_gene_trees]="$no_gene_trees"
        filtering_results_kyes_a+=('n_starting_gene_trees')
        #(( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done
	
	# 4.1.3 Populate the aln_models_h hash and aln_models_a array from *stats.tsv generated by compute_IQT_gene_tree_stats
	gene_tree_stats_file=$(find . -name \*stats.tsv -printf '%f\n')
	
        ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$non_recomb_FAA_alns_dir")
        output_files_a+=(gene_tree_stats_file)
        output_files_h[gene_tree_stats_file]=$(echo -e "$ed_dir\t$gene_tree_stats_file")

	print_start_time && msg "# populating the aln_models_h hash from $gene_tree_stats_file ..." PROGR BLUE

        while read -r aln _  _ _ model _; do
            aln="${aln/.\//}"
            aln="${aln%.log}" 
            aln_models_a+=("${aln/.\//}")
            aln_models_h["${aln/.\//}"]="$model"
        done < <(awk 'NR > 1' "$gene_tree_stats_file");
	
    fi # if/else [[ "$search_algorithm" == "F" ]]

    #remove trees with < 5 branches
    print_start_time && msg "# counting branches on $no_non_recomb_alns_perm_test gene trees ..." PROGR BLUE
    (( DEBUG > 0 )) && msg " > count_tree_branches $gene_tree_ext no_tree_branches.list &> /dev/null" DEBUG NC

    count_tree_branches "$gene_tree_ext" no_tree_branches.list # &> /dev/null
    [ ! -s no_tree_branches.list ] && install_Rlibs_msg no_tree_branches.list ape

    check_output no_tree_branches.list "$parent_PID"

    # remove trees with < 5 external branches (leaves)
     (( DEBUG > 0 )) && msg " >  removing trees with < 5 external branches (leaves)" DEBUG NC

    declare -a no_tree_counter2
    no_tree_counter2=()
    
    while read -r phy; do 
        [[ "$phy" =~ ^#Tree ]] && continue
	[ "$search_algorithm" == "F" ] && base="${phy//_allFT\.ph/}"
	[ "$search_algorithm" == "I" ] && base="${phy//\.treefile/}"
	print_start_time && msg " >>> will remove ${base}* because it has < 5 branches" WARNING LRED
        no_tree_counter2+=("$base")
	rm "${base}"*
    done < <(awk -v min_no_ext_branches="$min_no_ext_branches" 'BEGIN{FS="\t"; OFS="\t"}$7 < min_no_ext_branches{print $1}' no_tree_branches.list)
	
    if [[ "${#no_tree_counter2[@]}" -gt 0 ]]; then
        msg " >>> WARNING: there are ${#no_tree_counter2[@]} trees with < 1 internal branches (not real trees) that will be discarded ..." WARNING LRED
    fi
     
    filtering_results_h[n_trivial_gene_trees]="${#no_tree_counter2[@]}"
    filtering_results_kyes_a+=('n_trivial_gene_trees')

    filtering_results_h[n_non_trivial_gene_trees]=$((no_gene_trees - "${#no_tree_counter2[@]}"))
    filtering_results_kyes_a+=('n_non_trivial_gene_trees')
    #(( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done


    msg "" PROGR NC
    msg " >>>>>>>>>>>>>>> filter gene trees for outliers with kdetrees test <<<<<<<<<<<<<<< " PROGR YELLOW
    msg "" PROGR NC

    if [ "$search_algorithm" == "F" ]
    then
        # 4.1 generate the all_GTRG_trees.tre holding all source trees, which is required by kdetrees
        #     Make a check for the existence of the file to interrupt the pipeline if something has gone wrong
        (( DEBUG > 0 )) && msg " > cat ./*.ph > all_gene_trees.tre" DEBUG NC
        cat ./*.ph > all_gene_trees.tre
        check_output all_gene_trees.tre "$parent_PID"
        [ ! -s all_gene_trees.tre ] && exit 3
    else
        # 4.1 generate the all_IQT_trees.tre holding all source trees, which is required by kdetrees
        #     Make a check for the existence of the file to interrupt the pipeline if something has gone wrong
        (( DEBUG > 0 )) && msg " > cat ./*treefile > all_gene_trees.tre" DEBUG NC
	cat ./*.treefile > all_gene_trees.tre
        check_output all_gene_trees.tre "$parent_PID"
        [ ! -s all_gene_trees.tre ] && exit 3
    fi

    # 5.2 run_kdetrees.R at desired stringency
    print_start_time && msg "# running kde test ..." PROGR BLUE
    (( DEBUG > 0 )) && msg " > ${distrodir}/run_kdetrees.R ${gene_tree_ext} all_gene_trees.tre $kde_stringency &> /dev/null" DEBUG NC
    #{ "${distrodir}"/run_kdetrees.R "$gene_tree_ext" all_gene_trees.tre "$kde_stringency" &> /dev/null && return 0 ; }  # <FIXME>
    "${distrodir}"/run_kdetrees.R "$gene_tree_ext" all_gene_trees.tre "$kde_stringency" &> /dev/null || \
    { msg "WARNING: could not run ${distrodir}/run_kdetrees.R $gene_tree_ext all_gene_trees.tre $kde_stringency &> /dev/null" WARNING LRED ; }
    
    #[ ! -s kde_dfr_file_all_gene_trees.tre.tab ] && install_Rlibs_msg kde_dfr_file_all_gene_trees.tre.tab kdetrees,ape
    #check_output kde_dfr_file_all_gene_trees.tre.tab "$parent_PID"

    # Print a warning if kdetrees could not be run, but do not exit
    if [[ ! -s kde_stats_all_gene_trees.tre.out ]]
    then
        PRINT_KDE_ERR_MESSAGE=1
        msg "# WARNING: could not write kde_dfr_file_all_gene_trees.tre.tab; check that kdetrees and ape are propperly installed ..." WARNING LRED
        msg "# WARNING:      will arbitrarily set no_kde_outliers to 0, i.e. NO kde filtering applied to this run!" WARNING LRED
        msg "# This issue can be easily avoided by running the containerized version available from https://hub.docker.com/r/vinuesa/get_phylomarkers!" PROGR GREEN
    fi

    # Check how many outliers were detected by kdetrees
    if [ ! -s kde_dfr_file_all_gene_trees.tre.tab ]
    then
        no_kde_outliers=0
        no_kde_ok=$(wc -l < all_gene_trees.tre)
    else
        # 5.3 mv outliers to kde_outliers
        no_kde_outliers=$(grep -c outlier kde_dfr_file_all_gene_trees.tre.tab)
        no_kde_ok=$(grep -v outlier kde_dfr_file_all_gene_trees.tre.tab | grep -vc '^file')
    fi 
    ((DEBUG > 0 )) && msg "PRINT_KDE_ERR_MESSAGE: $PRINT_KDE_ERR_MESSAGE; no_kde_outliers:$no_kde_outliers; no_kde_ok:$no_kde_ok" DEBUG NC

    # 5.4 Check how many cdnAlns passed the test and separate into two subirectories those passing and failing the test
    if (( no_kde_outliers > 0 ))
    then
        print_start_time && msg "# making dir kde_outliers/ and moving $no_kde_outliers outlier files into it ..." PROGR BLUE
        mkdir kde_outliers || { msg "ERROR: could not mkdir kde_outliers" ERROR RED && exit 1 ; }

        if [ "$search_algorithm" == "F" ]; then
            while IFS= read -r f
            do
	        mv "${f}"* kde_outliers
	    done < <(grep outlier kde_dfr_file_all_gene_trees.tre.tab | cut -f1 | sed 's/_allFTlgG\.ph//')
	fi

	if [ "$search_algorithm" == "I" ]; then
            while IFS= read -r f
            do
                mv "${f}"* kde_outliers
            done < <(grep outlier kde_dfr_file_all_gene_trees.tre.tab | cut -f1 | sed 's/\.treefile//')
        fi
    fi
    
    if (( no_kde_outliers == 0 )); then
	print_start_time && msg " >>> there are no kde-test outliers ... " PROGR GREEN	
    fi

    if (( no_kde_ok > 0 ))
    then
        print_start_time && msg "# making dir kde_ok/ and linking $no_kde_ok selected files into it ..." PROGR BLUE
        mkdir kde_ok || { msg "ERROR: could not mkdir kde_ok" ERROR RED && exit 1 ; }
        cd kde_ok || { msg "ERROR: could not cd into kde_ok" ERROR RED && exit 1 ; }
        ln -s ../*."${gene_tree_ext}" .
       
        print_start_time && msg "# labeling $no_kde_ok gene trees in dir kde_ok/ ..." PROGR BLUE
        (( DEBUG > 0 )) \
	  && msg " > ${distrodir}/run_parallel_cmmds.pl ${gene_tree_ext} 'add_labels2tree.pl ../../../tree_labels.list $file' $n_cores &> /dev/null" DEBUG NC
	  { "${distrodir}"/run_parallel_cmmds.pl "${gene_tree_ext}" 'add_labels2tree.pl ../../../tree_labels.list $file' "$n_cores" &> /dev/null && return 0 ; }
         

	# remove symbolic links to cleanup kde_ok/
        #for f in $(./*."${gene_tree_ext}" | grep -v "_ed\.${gene_tree_ext}"); do rm "$f"; done
        find . -type l -delete
	
        cd .. || { msg "ERROR: could not cd ../" ERROR RED && exit 1 ; }
    else
        PRINT_KDE_ERR_MESSAGE=1
	#print_start_time && msg "# ERROR There are $no_kde_ok gene trees producing non-significant kde-test results! Increase the actual -k $kde_stringency value. Will stop here!" ERROR RED
        #    exit 5
    fi

    filtering_results_h[n_KDE_gene_tree_outliers]="$no_kde_outliers"
    filtering_results_kyes_a+=('n_KDE_gene_tree_outliers')

    filtering_results_h[n_KDE_gene_trees_OK]="$no_kde_ok"
    filtering_results_kyes_a+=('n_KDE_gene_trees_OK')
    #(( DEBUG > 0 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done

    ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$non_recomb_FAA_alns_dir")
    output_files_a+=(kdetrees_tests_on_all_gene_trees)
    output_files_h[kdetrees_tests_on_all_gene_trees]=$(echo -e "$ed_dir\tkde_dfr_file_all_gene_trees.tre.tab")

    read_svg_figs_into_hash "$ed_dir" figs_a figs_h

    #---------------------------------------#
    # >>> BLOCK 5.2: PROT PHYLOGENETICS <<< #
    #---------------------------------------#
    wkdir=$(pwd)

    msg "" PROGR NC
    msg " >>>>>>>>>>>>>>> filter gene trees by phylogenetic signal content <<<<<<<<<<<<<<< " PROGR YELLOW
    msg "" PROGR NC

    print_start_time && msg "# computing tree support values ..." PROGR BLUE
    (( DEBUG > 0 )) && msg " > compute_suppValStas_and_RF-dist.R $wkdir 1 fasta ${gene_tree_ext} 1 &> /dev/null" DEBUG NC
    compute_suppValStas_and_RF-dist.R "$wkdir" 1 faaln "${gene_tree_ext}" 1 &> /dev/null

    print_start_time && msg "# writing summary tables ..." PROGR BLUE
    min_supp_val_perc="${min_supp_val#0.}"
    no_digits="${#min_supp_val_perc}"
    (( no_digits == 1 )) && min_supp_val_perc="${min_supp_val_perc}0"

    # NOTE: IQ-TREE -alrt 1000 provides support values in 1-100 scale, not as 0-1 as FT!
    #	    therefore we convert IQT-bases SH-alrt values to 0-1 scale for consistency
    [ "$search_algorithm" == "I" ] && min_supp_val=$(echo "$min_supp_val * 100" | bc)

    awk -v min_supp_val="$min_supp_val" '$2 >= min_supp_val' sorted_aggregated_support_values4loci.tab > sorted_aggregated_support_values4loci_ge"${min_supp_val_perc}"perc.tab
    check_output "sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab" "$parent_PID"

    no_top_markers=$(perl -lne 'END{print $.}' "sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab")
    top_markers_dir="top_${no_top_markers}_markers_ge${min_supp_val_perc}perc"
    top_markers_tab=$(ls "sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab")

    ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$wkdir")
    output_files_a+=(sorted_aggregated_support_values_for_top_markers)
    output_files_h[sorted_aggregated_support_values_for_top_markers]=$(echo -e "$ed_dir\t$top_markers_tab")

    read_svg_figs_into_hash "$ed_dir" figs_a figs_h

    filtering_results_h[n_gene_trees_with_low_median_support]=$((no_kde_ok - no_top_markers))
    filtering_results_kyes_a+=('n_gene_trees_with_low_median_support')

    filtering_results_h[n_top_markers_median_support]="$no_top_markers"
    filtering_results_kyes_a+=('n_top_markers_median_support')     
    #(( DEBUG > 1 )) && for k in "${filtering_results_kyes_a[@]}"; do echo "$k: ${filtering_results_h[$k]}"; done    


    # Run likelihood mapping, only if algorithm == I (IQ-TREE)
    #	 to asses tree-likeness and phylogenetic signal
    if [ "$search_algorithm" == "I" ]
    then
    	print_start_time && msg "# computing likelihood mappings to asses tree-likeness and phylogenetic signal ..." PROGR BLUE
    	
    	# Run IQ-TREE -lmap and populate the aln_lmappings_a array and aln_lmappings_h hash
    	#  the aln_models_a array and aln_models_h were populated from *stats.tsv, after running compute_IQT_gene_tree_stats
    	for a in "${aln_models_a[@]}"; do
    	    if [ -s "$a" ]; then
    		((DEBUG > 1)) && echo "iqtree -s $a -m ${aln_models_h[$a]} -te ${a}.treefile -lmap $lmap_sampling -T $n_cores --prefix lmapping_test_${a%.*} --quiet"
    		iqtree -s "$a" -m "${aln_models_h[$a]}" -te "${a}".treefile -lmap "$lmap_sampling" -T "$n_cores" --prefix lmapping_test_"${a%.*}" --quiet
    
    		# parse AU test results from iqtree files
    		aln_lmappings_a+=("$a")
    		aln_lmappings_h["$a"]=$(grep 'Number of fully resolved' lmapping_test_"${a%.*}".iqtree | sed 's/Number of fully.*=//; s/%)//')
    	    else
    		continue
    	    fi
    	done 

    	print_start_time && msg "# parsing likelihood mapping results, and writing summary table ..." PROGR BLUE
    	# Print the likelihood mapping results of each gene tree to a tsv file
    	for a in "${aln_lmappings_a[@]}"; do
    	    echo -e "$a\t${aln_lmappings_h[$a]}"
    	done > geneTree_lmapping_tests.tsv

    	check_output geneTree_lmapping_tests.tsv "$parent_PID"
    	ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$wkdir")
    	output_files_a+=(geneTree_lmapping_tests)
    	output_files_h[geneTree_lmapping_tests]=$(echo -e "$ed_dir\tgeneTree_lmapping_tests.tsv")

    	# cleanup the lmappint_test_files
    	[ -s geneTree_lmapping_tests.tsv ] && rm lmapping_test_* 
    	
    	# filter  lmapping results >= \$min_support_val_perc
    	print_start_time && msg "# parsing likelihood mapping results table to identify trees with >= $min_supp_val_perc fully resolved quartets ..." PROGR BLUE
    	awk -v min="$min_supp_val_perc" 'BEGIN{FS=OFS="\t"}$2 >= min' geneTree_lmapping_tests.tsv > \
    	  geneTrees_passing_lmapping_tests_ge_"${min_supp_val_perc}".tsv
    	
    	check_output geneTrees_passing_lmapping_tests_ge_"${min_supp_val_perc}".tsv "$parent_PID"
    	ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$wkdir")
    	output_files_a+=(geneTree_passing_lmapping_tests)
    	output_files_h[geneTree_passing_lmapping_tests]=$(echo -e "$ed_dir\tgeneTrees_passing_lmapping_tests_ge_${min_supp_val_perc}.tsv")
    	
    	n_lmapping_tests=$(wc -l < geneTree_lmapping_tests.tsv)
    	n_alns_passing_lmapping_tests=$(wc -l < geneTrees_passing_lmapping_tests_ge_"${min_supp_val_perc}".tsv)
    	n_alns_failing_lmapping_tests=$((n_lmapping_tests - n_alns_passing_lmapping_tests))
    	
    	msg " >>> $n_alns_passing_lmapping_tests alignments passed the likelihood mapping test at >= ${min_supp_val_perc}% out of $n_lmapping_tests ... " PROGR GREEN

    	filtering_results_kyes_a+=('n_alns_failing_lmapping_tests') 
    	filtering_results_h[n_alns_failing_lmapping_tests]="$n_alns_failing_lmapping_tests"

    	filtering_results_kyes_a+=('n_alns_passing_lmapping_tests') 
    	filtering_results_h[n_alns_passing_lmapping_tests]="$n_alns_passing_lmapping_tests"


    	# Filter alignments passing both the likelihood mapping (lmap) AND
    	#   the min. median bipartition support tests >= min_supp_val_perc
    	# 1. filter by lmap
    	while read -r id; do 
    	    [ -z "$id" ] && continue
    	    [[ "$id" =~ [^0-9]+ ]] && continue
    	    ((DEBUG > 1)) && msg "# filter by lmap: running: alns_passing_lmap_and_suppval_h[$id]++" DEBUG NC
    	    alns_passing_lmap_and_suppval_h["$id"]=1
    	done < <(cut -d_ -f1 geneTrees_passing_lmapping_tests_ge_"${min_supp_val_perc}".tsv)
    
    	# 2. filter by min_supp_val
    	while read -r id; do 
    	    [ -z "$id" ] && continue
    	    id=${id//\"/}
    	    [[ "$id" =~ [^0-9]+ ]] && continue
    	    ((DEBUG > 1)) && msg "# filter by min_supp_val: running: alns_passing_lmap_and_suppval_h[$id]++" DEBUG NC
    	    ((alns_passing_lmap_and_suppval_h["$id"]++)) || alns_passing_lmap_and_suppval_h["$id"]=1  # requires this test if id is unbound
    	done < <(cut -f1 "$top_markers_tab") # sorted_aggregated_support_values4loci_ge${min_supp_val_perc}perc.tab
    	
    	if ((DEBUG > 1)); then
    	    for a in "${!alns_passing_lmap_and_suppval_h[@]}"; do
    		printf "%s\t%d\n" "$a" "${alns_passing_lmap_and_suppval_h[$a]}"
    	    done
    	fi
    	# 3. fill the array of alignments passing both phylogenetic signal content tests (i.e. "${alns_passing_lmap_and_suppval_h[$a]}" == 2)
    	# alns_passing_lmap_and_suppval_a+=($(for a in "${!alns_passing_lmap_and_suppval_h[@]}"; do (("${alns_passing_lmap_and_suppval_h[$a]}" == 2 )) && echo "${a}"; done))
    	mapfile -t alns_passing_lmap_and_suppval_a < <(for a in "${!alns_passing_lmap_and_suppval_h[@]}"; do (("${alns_passing_lmap_and_suppval_h[$a]}" == 2 )) && echo "${a}"; done)
    	# 4. Reset the top_markers_dir and no_top_markers when runnig both phylogenetic signal filters under -A I (IQ-TREE)
    	top_markers_dir=top_"${#alns_passing_lmap_and_suppval_a[@]}"_markers_ge"${min_supp_val_perc}"perc
    	no_top_markers="${#alns_passing_lmap_and_suppval_a[@]}"
    	
    	msg " >>> $no_top_markers alignments passed both the lmapping and median bipartition support tests at >= ${min_supp_val_perc}% out of $n_lmapping_tests ..." PROGR GREEN

    	filtering_results_kyes_a+=('n_alns_passing_lmapping_and_bipart_support_tests')      
    	filtering_results_h[n_alns_passing_lmapping_and_bipart_support_tests]="$no_top_markers"
    fi # [ "$search_algorithm" == "I" ]


    # >>> 5.2 move top-ranking markers to $top_markers_dir
    print_start_time && msg "# making dir $top_markers_dir and moving $no_top_markers top markers into it ..." PROGR LBLUE
    { mkdir "$top_markers_dir" && cd "$top_markers_dir" ; } || { msg "ERROR: cannot cd into $top_markers_dir" ERROR RED && exit 1 ; }
    top_markers_dir=$(pwd)
    if [ "$search_algorithm" == "F" ] # FastTree
    then
    	ln -s ../"$top_markers_tab" .
    	while read -r id _; do 
    	     [[ "$id" =~ loci ]] && continue
    	     id=${id//\"/}
    	 
    	     # -h doesn't work with globs. Use a for loop
    	     #for i in $(find .. -maxdepth 1 -name "${id}"\* -printf "%f\n")
    	     while read -r i; do
    		 (( DEBUG > 0 )) && msg " > reading top_markers_tab:$top_markers_tab in top_markers_dir:$top_markers_dir; running: ln -s ../${i} ." DEBUG NC
    		 if [ ! -h "$i" ]
    		 then
    		     ln -s ../"$i" .
    		 else
    		     continue
    		 fi
    	     done < <(find .. -maxdepth 1 -name "${id}"\* -printf "%f\n")
    	done < "$top_markers_tab"
    else # IQ-Tree
    	for id in "${alns_passing_lmap_and_suppval_a[@]}"
    	do 
    	    while read -r i
    	    do
    		(( DEBUG > 0 )) && msg " > reading top_markers_tab:$top_markers_tab in top_markers_dir:$top_markers_dir; running: ln -s ../${i} ." DEBUG NC
    		if [ ! -h "$i" ]
    		then
    		    ln -s ../"$i" .
    		else
    		    continue
    		fi
    	    done < <(find .. -maxdepth 1 -name "${id}"\* -printf "%f\n")
    	done
    fi

    # set a trap in case the script exits here (see SC2064 for correct quoting)
    trap 'cleanup_trap "$(pwd)" PHYLO_SIGNAL' ABRT EXIT HUP INT QUIT TERM
    (( no_top_markers < 2 )) \
    && print_start_time \
    && msg " >>> Warning: There are less than 2 top markers. Relax the filtering thresholds. Will exit now!" WARNING LRED && exit 3

    msg "" PROGR NC
    msg " >>>>>>>>>>>>>>> generate supermatrix from $no_top_markers concatenated, top-ranking alignments <<<<<<<<<<<<<<< " PROGR YELLOW
    msg "" PROGR NC

    # >>> 5.3 generate supermatrix (concatenated alignment)
    print_start_time && msg "# concatenating $no_top_markers top markers into supermatrix ..." PROGR BLUE
    (( DEBUG > 0 )) && msg " > concat_alns faaln $parent_PID &> /dev/null" DEBUG NC
    concat_alns faaln "$parent_PID" &> /dev/null
    
    output_files_a+=(prot_concat_aln_faa)
    output_files_h[prot_concat_aln_faa]=$(echo -e "$ed_dir\tconcat_protAlns.faa")

    # >>> 5.4 remove uninformative sites from the concatenated alignment to speed up computation
    print_start_time && msg "# removing uninformative sites from concatenated alignment ..." PROGR BLUE
    (( DEBUG > 0 )) && msg " > ${distrodir}/remove_uninformative_sites_from_aln.pl < concat_protAlns.faa > concat_protAlns.faainf" DEBUG NC
    "${distrodir}"/remove_uninformative_sites_from_aln.pl < concat_protAlns.faa > concat_protAlns.faainf
    check_output concat_protAlns.faainf "$parent_PID"
    output_files_a+=(prot_concat_aln_faainf)
    output_files_h[prot_concat_aln_faainf]=$(echo -e "$ed_dir\tconcat_protAlns.faainf")

    # set a trap in case the script exits here (see SC2064 for correct quoting)
    trap 'cleanup_trap "$(pwd)" PHYLO_SUPERMATRIX' ABRT EXIT HUP INT QUIT TERM
    [ ! -s concat_protAlns.faainf ] && print_start_time && msg " >>> ERROR: The expected file concat_protAlns.faainf was not produced! will exit now!" ERROR RED && exit 3


    #::::::::::::::::::::::::::::::::::::::::::#
    # >>> FastTree concatProt species tree <<< #
    #::::::::::::::::::::::::::::::::::::::::::#
    if [ "$search_algorithm" == "F" ]
    then
        print_start_time && msg "# running compute_MJRC_tree ph $search_algorithm ..." PROGR BLUE
	compute_MJRC_tree ph "$search_algorithm" 

        ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$top_markers_dir")

	output_files_a+=(concat_prot_gene_trees_FT_nwk)
        output_files_h[concat_prot_gene_trees_FT_nwk]=$(echo -e "$ed_dir\talltrees.nwk")

	# >>> ASTRAL <<< #
	msg "" PROGR NC
	msg " >>>>>>>>>>>>>>> Computing ASTRAL species tree on ${no_top_markers} top marker gene trees <<<<<<<<<<<<<<< " PROGR YELLOW
	msg "" PROGR NC
	
        # compute ASTRAL species tree on the alltrees.nwk file
        if [ -s alltrees.nwk ]
        then
           print_start_time && msg "# computing ASTRAL species tree from ${no_top_markers} top marker gene trees ..." PROGR BLUE
           (( DEBUG > 0 )) && msg " > run_ASTRAL alltrees.nwk $no_top_markers $tree_labels_dir $n_cores" DEBUG NC
           run_ASTRAL alltrees.nwk "${no_top_markers}" "$tree_labels_dir" "$n_cores"
        else
           msg " >>> WARNING: file alltrees.nwk was not found; cannot run ASTRAL ..." WARNING LRED
        fi

        output_files_a+=(ASTRAL4_species_tree)
        output_files_h[ASTRAL4_species_tree]=$(echo -e "$ed_dir\tastral4_top${no_top_markers}geneTrees_ed.sptree")

        output_files_a+=(wASTRAL_species_tree)
        output_files_h[wASTRAL_species_tree]=$(echo -e "$ed_dir\twastral_top${no_top_markers}geneTrees_ed.sptree")

        output_files_a+=(wASTRAL_species_tree)
        output_files_h[wASTRAL_species_tree]=$(echo -e "$ed_dir\twastral_top${no_top_markers}geneTrees_ed.sptree")

        output_files_a+=(IQTree_constrained_by_wASTRALspTree)
        output_files_h[IQTree_constrained_by_wASTRALspTree]=$(echo -e "$ed_dir\tIQTree_constrained_by_wASTRALspTree_ed.treefile")
		
        msg "" PROGR NC
        msg " >>>>>>>>>>>>>>> FastTree run on $no_top_markers concatenated $mol_type alignments to estimate the species tree <<<<<<<<<<<<<<< " PROGR YELLOW
        msg "" PROGR NC

        # 5.4 run FasTree under the LG+G model
        print_start_time && msg "# running FastTree on $no_top_markers concatenated $mol_type alignments with $search_thoroughness thoroughness. This may take a while ..." PROGR BLUE

        if [ "$search_thoroughness" == "high" ]
        then
            "$bindir"/FastTree -quiet -lg -bionj -slow -slownni -gamma -mlacc 3 -spr "$spr" -sprlength "$spr_length" -log "${tree_prefix}"_nonRecomb_KdeFilt_protAlns_FTlgG.log \
	    < concat_protAlns.faainf > "${tree_prefix}"_nonRecomb_KdeFilt_protAlns_FTlgG.ph
        fi

        if [ "$search_thoroughness" == "medium" ]
        then
            "$bindir"/FastTree -quiet -lg -bionj -slownni -gamma -mlacc 2 -spr "$spr" -sprlength "$spr_length" -log "${tree_prefix}"_nonRecomb_KdeFilt_protAlns_FTlgG.log \
	    < concat_protAlns.faainf > "${tree_prefix}"_nonRecomb_KdeFilt_protAlns_FTlgG.ph
        fi

        if [ "$search_thoroughness" == "low" ]
        then
            "$bindir"/FastTree -quiet -lg -bionj -gamma -spr "$spr" -sprlength "$spr_length" -log "${tree_prefix}"_nonRecomb_KdeFilt_protAlns_FTlgG.log \
	    < concat_protAlns.faainf > "${tree_prefix}"_nonRecomb_KdeFilt_protAlns_FTlgG.ph
        fi

        if [ "$search_thoroughness" == "lowest" ]
        then
            "$bindir"/FastTree -quiet -lg -gamma -mlnni 4 -log "${tree_prefix}"_nonRecomb_KdeFilt_protAlns_FTlgG.log < concat_protAlns.faainf > \
	    "${tree_prefix}"_nonRecomb_KdeFilt_protAlns_FTlgG.ph
        fi

        check_output "${tree_prefix}"_nonRecomb_KdeFilt_protAlns_FTlgG.ph "$parent_PID"

        if [[ -s "${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.log" ]] && [[ -s "${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.ph" ]]
        then
            # lnL=$(grep ML_Lengths2 "${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.log" | grep TreeLogLk | sed 's/TreeLogLk[[:space:]]ML_Lengths2[[:space:]]//')
            # lnL=$(grep '^Gamma20LogLk' "${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.log" |awk '{print $2}')
	    lnL=$(awk '/^Gamma20LogLk/{print $2}' "${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.log")
            msg " >>> lnL for ${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.ph = $lnL" PROGR GREEN
        else
            msg " >>> WARNING: ${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.log could not be produced!" WARNING LRED
        fi

        print_start_time && msg "# Adding labels back to tree ..." PROGR LBLUE
        lmsg=(" > add_labels2tree.pl ${tree_labels_dir}/tree_labels.list ${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.ph &> /dev/null")
        (( DEBUG > 0 )) && msg "${lmsg[*]}" DEBUG NC
        add_labels2tree.pl "${tree_labels_dir}"/tree_labels.list "${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.ph" &> /dev/null

        [ -s "${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG_ed.ph" ] && \
        mv "${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG_ed.ph" "${tree_prefix}_${no_top_markers}nonRecomb_KdeFilt_protAlns_FTlgG.spTree"
        mv "${tree_prefix}_nonRecomb_KdeFilt_protAlns_FTlgG.ph" "${tree_prefix}_${no_top_markers}nonRecomb_KdeFilt_protAlns_FTlgG_numbered.tre"

        check_output "${tree_prefix}_${no_top_markers}nonRecomb_KdeFilt_protAlns_FTlgG.spTree" "$parent_PID"
        output_files_a+=(concat_protAln_FT_species_tree)
        output_files_h[concat_protAln_FT_species_tree]=$(echo -e "$ed_dir\t${tree_prefix}_${no_top_markers}nonRecomb_KdeFilt_protAlns_FTlgG.spTree")

        msg " >>> found in dir $top_markers_dir ..." PROGR GREEN

        (( DEBUG > 0 )) && msg " > compute_suppValStas_and_RF-dist.R $top_markers_dir 2 faaln ph 1 &> /dev/null" DEBUG NC
        { "${distrodir}"/compute_suppValStas_and_RF-dist.R "$top_markers_dir" 2 faaln ph 1 &> /dev/null && return 0 ; }
        
	read_svg_figs_into_hash "$ed_dir" figs_a figs_h

    fi # [ "$search_algorithm" == "F" ]

    #:::::::::::::::::::::::::::::::::::::::::#
    # >>> IQ-TREE concatProt species tree <<< #
    #:::::::::::::::::::::::::::::::::::::::::#

    if [ "$search_algorithm" == "I" ]
    then
        print_start_time && msg "# running compute_MJRC_tree treefile $search_algorithm ..." PROGR BLUE
        compute_MJRC_tree treefile "$search_algorithm" 

        ed_dir=$(rm_top_dir_prefix_from_wkdir "$top_dir" "$top_markers_dir")
	output_files_a+=(concat_prot_gene_trees_IQT_nwk)
        output_files_h[concat_prot_gene_trees_IQT_nwk]=$(echo -e "$ed_dir\talltrees.nwk")
	
	msg "" PROGR NC
        msg " >>>>>>>>>>>>>>> Computing ASTRAL species tree on ${no_top_markers} top marker gene trees <<<<<<<<<<<<<<< " PROGR YELLOW
        msg "" PROGR NC

        # compute ASTRAL species tree on the alltrees.nwk file
        if [ -s alltrees.nwk ]
        then
            print_start_time && msg "# computing ASTRAL species tree from ${no_top_markers} top marker gene trees ..." PROGR BLUE
            (( DEBUG > 0 )) && msg " > run_ASTRAL alltrees.nwk $no_top_markers $tree_labels_dir $n_cores" DEBUG NC
	        run_ASTRAL alltrees.nwk "${no_top_markers}" "$tree_labels_dir" "$n_cores"
        else
           msg " >>> WARNING: file alltrees.nwk was not found; cannot run ASTRAL ..." WARNING LRED
        fi

        output_files_a+=(ASTRAL4_species_tree)
        output_files_h[ASTRAL4_species_tree]=$(echo -e "$ed_dir\tastral4_top${no_top_markers}geneTrees_ed.sptree")

        output_files_a+=(wASTRAL_species_tree)
        output_files_h[wASTRAL_species_tree]=$(echo -e "$ed_dir\twastral_top${no_top_markers}geneTrees_ed.sptree")

        output_files_a+=(concat_prot_aln_model_selection_on_wastral_usertree_IQT_logfile)
        output_files_h[concat_prot_aln_model_selection_on_wastral_usertree_IQT_logfile]=$(echo -e "$top_markers_dir\twastral_usertree_concat_model_selection.log")

        output_files_a+=(IQTree_constrained_by_wASTRALspTree)
        output_files_h[IQTree_constrained_by_wASTRALspTree]=$(echo -e "$ed_dir\tIQTree_constrained_by_wASTRALspTree_ed.treefile")
	
	
        # 5.5 run IQ-tree in addition to ASTRAL, if requested
        msg "" PROGR NC
        msg " >>>>>>>>>>>>>>> IQ-TREE + ModelFinder run on $no_top_markers concatenated $mol_type alignments to estimate the species tree <<<<<<<<<<<<<<< " PROGR YELLOW
        msg "" PROGR NC
               
        print_start_time && msg "# running ModelFinder on the $no_top_markers concatenated $mol_type alignments with $IQT_models. This will take a while ..." PROGR BLUE       
        iqtree -s concat_protAlns.faainf -st PROT -mset "$IQT_models" -m MF -T "$IQT_threads" -n 0 &> /dev/null       
        check_output concat_protAlns.faainf.log "$parent_PID"

        output_files_a+=(concat_protAlns_IQT_faainf_logfile)
        output_files_h[concat_protAlns_IQT_faainf_logfile]=$(echo -e "$ed_dir\tconcat_protAlns.faainf.log")

        best_model=$(grep '^Best-fit model' concat_protAlns.faainf.log | cut -d' ' -f 3)
        msg " >>> Best-fit model: ${best_model} ..." PROGR GREEN

        { mkdir iqtree_abayes && cd iqtree_abayes ; }|| { msg "ERROR: cannot cd into iqtree_abayes" ERROR RED && exit 1 ; }
        ln -s ../concat_protAlns.faainf .

        if [ "$search_thoroughness" == "high" ]
        then
      	    lmsg=("# will launch $nrep_IQT_searches independent IQ-TREE searches on the supermatrix with best model ${best_model} --abayes -B 1000! 
	             This will take a while ...")
      	    print_start_time && msg "${lmsg[*]}" PROGR BLUE

      	    # run nrep_IQT_searches IQ-TREE searches under the best-fit model found
      	    for ((rep=1;rep<=nrep_IQT_searches;rep++))
      	    do
      	       lmsg=(" > iqtree -s concat_protAlns.faainf -st PROT -m $best_model --abayes -B 1000 -T $IQT_threads --prefix abayes_run${rep} &> /dev/null")
      	       print_start_time && msg "${lmsg[*]}" PROGR LBLUE
      	       iqtree -s concat_protAlns.faainf -st PROT -m "$best_model" --abayes -B 1000 -T "$IQT_threads" --prefix abayes_run"${rep}" &> /dev/null
      	    done

      	    grep '^BEST SCORE' ./*log | sed 's#./##' | sort -nrk5 > sorted_IQ-TREE_searches.out
      	    check_output sorted_IQ-TREE_searches.out "$parent_PID"
	   
      	    best_search=$(head -1 sorted_IQ-TREE_searches.out)
      	    best_search_base_name=$(head -1 sorted_IQ-TREE_searches.out | cut -d\. -f 1)

      	    msg "# >>> Best IQ-TREE run was: $best_search ..." PROGR GREEN

      	    best_tree_file="${tree_prefix}_${best_search_base_name}_nonRecomb_KdeFilt_${no_top_markers}concat_protAlns_iqtree_${best_model}.spTree"
	    numbered_nwk="${tree_prefix}_${best_search_base_name}_nonRecomb_KdeFilt_${no_top_markers}concat_protAlns_iqtree_${best_model}_numbered.nwk"
      	    cp "${best_search_base_name}.treefile" "$best_tree_file"
	    cp "${best_search_base_name}.treefile" "$numbered_nwk"

      	    print_start_time && msg "# Adding labels back to ${best_tree_file} ..." PROGR BLUE
   	    (( DEBUG > 0 )) && msg " > ${distrodir}/add_labels2tree.pl ${tree_labels_dir}/tree_labels.list ${best_tree_file} &> /dev/null" DEBUG NC
   	    "${distrodir}"/add_labels2tree.pl "${tree_labels_dir}"/tree_labels.list "$best_tree_file" &> /dev/null
	   
	    sp_tree=$(ls ./*ed.spTree)
      	    check_output "$sp_tree" "$parent_PID"
            output_files_a+=(concat_protAlns_IQT_spTree)
            output_files_h[concat_protAlns_IQT_spTree]=$(echo -e "$ed_dir\t$sp_tree")

      	    cp "$sp_tree" "$numbered_nwk" "$top_markers_dir"
      	    cd "$top_markers_dir" || { msg "ERROR: cannot cd into $top_markers_dir" ERROR RED && exit 1 ; }
      	    rm -rf iqtree_abayes concat_protAlns.faainf.treefile concat_protAlns.faainf.uniqueseq.phy ./*ckp.gz

            read_svg_figs_into_hash "$ed_dir" figs_a figs_h
        else
    	    print_start_time && msg "# running IQ-tree on the concatenated alignment with best model ${best_model} --abayes -B 1000. This will take a while ..." PROGR BLUE

    	    print_start_time && msg "# running: iqtree -s concat_protAlns.faainf -st PROT -m $best_model --abayes -B 1000 -T $IQT_threads --prefix iqtree_abayes &> /dev/null  ..." PROGR BLUE
    	    iqtree -s concat_protAlns.faainf -st PROT -m "$best_model" --abayes -B 1000 -T "$IQT_threads" --prefix iqtree_abayes &> /dev/null

    	    best_tree_file="${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}concat_protAlns_iqtree_${best_model}.spTree"
	    numbered_nwk="${tree_prefix}_nonRecomb_KdeFilt_${no_top_markers}concat_protAlns_iqtree_${best_model}_numbered.nwk"
    	    cp iqtree_abayes.treefile "${best_tree_file}"
	    cp iqtree_abayes.treefile "$numbered_nwk"

    	    print_start_time && msg "# Adding labels back to ${best_tree_file} ..." PROGR BLUE "$logdir" "$dir_suffix"
   	    (( DEBUG > 0 )) && msg " > ${distrodir}/add_labels2tree.pl ${tree_labels_dir}/tree_labels.list ${best_tree_file} &> /dev/null" DEBUG NC "$logdir" "$dir_suffix"
   	    "${distrodir}"/add_labels2tree.pl "${tree_labels_dir}"/tree_labels.list "${best_tree_file}" &> /dev/null
	  
	    sp_tree=$(ls ./*ed.spTree)

    	    check_output "$sp_tree" "$parent_PID"
            output_files_a+=(concat_protAlns_IQT_spTree)
            output_files_h[concat_protAlns_IQT_spTree]=$(echo -e "$ed_dir\t$sp_tree")

    	    cp "$sp_tree" "$numbered_nwk" "$top_markers_dir"
    	    cd "$top_markers_dir" || { msg "ERROR: cannot cd into $top_markers_dir" ERROR RED && exit 1 ; }
    	    rm -rf iqtree_abayes concat_protAlns.faainf.treefile concat_protAlns.faainf.uniqueseq.phy ./*ckp.gz
	  
	    print_start_time && msg "# computing the mean support values and RF-distances of each gene tree to the concatenated tree ..." PROGR BLUE
	    (( DEBUG > 0 )) && msg " > compute_suppValStas_and_RF-dist.R $top_markers_dir 2 fasta treefile 1 &> /dev/null" DEBUG NC
            "$distrodir"/compute_suppValStas_and_RF-dist.R "$top_markers_dir" 2 fasta ph 1 &> /dev/null

 
        fi # if/else [ "$search_thoroughness" == "high" ]
        read_svg_figs_into_hash "$ed_dir" figs_a figs_h
	
    fi # if [ "$search_algorithm" == "I" ]

    # >>> 5.9 CLEANUP <<< #
    # >>> from version >= v2.8.4.0_2024-04-20
    #	  cleanup is performed by trap calls to trap cleanup_trap

fi # [ "$mol_type" == "PROT" ]


#-------------------------------------------#
# >>> BLOCK 6: PIPELINE ENDING MESSAGES <<< #
#-------------------------------------------#
if (( PRINT_KDE_ERR_MESSAGE == 1 ))
then 
    msg "# WARNING REMAINDER: run_kdetrees.R could not write kde_dfr_file_all_gene_trees.tre.tab; check that kdetrees and ape packages are propperly installed ..." WARNING LRED
    msg "#                    This run could therefore not apply kde filtering!" WARNING LRED
    msg "# This issue can be easily avoided by running the containerized version available from https://hub.docker.com/r/vinuesa/get_phylomarkers!" PROGR GREEN
fi

# print the pipeline's filtering overview
print_start_time && msg "# Overview of the pipeline's filtering process:" PROGR LBLUE
for k in "${filtering_results_kyes_a[@]}"
do
    msg "$k: ${filtering_results_h[$k]}" PROGR YELLOW
done

# write pipeline_filtering_overview.tsv to file 
for k in "${filtering_results_kyes_a[@]}"
do
    echo -e "$k\t${filtering_results_h[$k]}"
done > pipeline_filtering_overview.tsv
check_output pipeline_filtering_overview.tsv "$parent_PID"

print_start_time && msg "# Overview of the pipeline's key output files (without directories):" PROGR LBLUE
for k in  "${output_files_a[@]}"
do
   msg "${k}: ${output_files_h[$k]}" PROGR YELLOW
done | awk '{print $1, $3}' #| column -t -s $'\t' # skip path for tidyer screen output

# write pipeline_filtering_overview.tsv to file 
for k in  "${output_files_a[@]}"
do
   echo -e "$k\t${output_files_h[$k]}"
done > pipeline_output_files_overview.tsv
check_output pipeline_output_files_overview.tsv "$parent_PID"

print_start_time && msg "# Overview of the figures generated by the pipeline (without directories):" PROGR LBLUE
for k in "${figs_a[@]}"; do
     msg "$k:  ${figs_h[$k]}" PROGR YELLOW
done | awk '{print $1, $3}' #| column -t -s $'\t' # skip path for tidyer screen output

for k in "${figs_a[@]}"; do
    echo -e "$k\t${figs_h[$k]}"
done > pipeline_figure_files_overview.tsv
check_output pipeline_figure_files_overview.tsv "$parent_PID"


# compute the elapsed time since the script was fired
end_time=$(date +%s)
secs=$((end_time-start_time))

#printf '%dh:%dm:%ds\n' $(($secs/3600)) $(($secs%3600/60)) $(($secs%60))
msg "" PROGR NC
msg " >>> Total runtime of $progname:" PROGR LBLUE
printf '%dh:%dm:%ds\n' "$((secs/3600))" "$((secs%3600/60))" "$((secs%60))" | tee -a "${logdir}"/get_phylomarkers_run_"${dir_suffix}"_"${TIMESTAMP_SHORT}".log
echo

# Set a trap for final cleanup and print_citation (called by by trap "cleanup_trap") (see SC2064 for correct quoting)
if ((runmode == 1)); then
    trap 'cleanup_trap "$top_markers_dir" END' ABRT EXIT HUP INT QUIT TERM
elif ((runmode == 2)); then
    # <TODO>: need to update to enter and cleanup the non_recomb_cdn_alns/PopGen/neutral_loci_X directory
    trap 'cleanup_trap "$neutral_loci_dir" END' ABRT EXIT HUP INT QUIT TERM
fi
exit 0 # Do not remove: triggers the cleanup_trap at END-OF-SCRIPT
