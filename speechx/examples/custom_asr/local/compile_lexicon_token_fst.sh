#!/bin/bash
# Copyright 2015       Yajie Miao    (Carnegie Mellon University)

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# This script compiles the lexicon and CTC tokens into FSTs. FST compiling slightly differs between the
# phoneme and character-based lexicons.
set -eo pipefail
. utils/parse_options.sh

#This script uses three arguments. If the three are not present then exit. 
#The three requirements are as mentioned in the below help message.
if [ $# -ne 3 ]; then
  echo "usage: utils/fst/compile_lexicon_token_fst.sh <dict-src-dir> <tmp-dir> <lang-dir>"
  echo "e.g.: utils/fst/compile_lexicon_token_fst.sh data/local/dict data/local/lang_tmp data/lang"
  echo "<dict-src-dir> should contain the following files:"
  echo "lexicon.txt lexicon_numbers.txt units.txt"
  echo "options: "
  exit 1;
fi

srcdir=$1  #points to the folder having lexicons and tokens files
tmpdir=$2  #points to the temp folder
dir=$3     #points to the final directory in which the resultant fsts will be stored.
mkdir -p $dir $tmpdir

[ -f path.sh ] && . ./path.sh


#copying the tokens file into our final directory
cp $srcdir/units.txt $dir

# Add probabilities to lexicon entries. There is in fact no point of doing this here since all the entries have 1.0.
# But utils/make_lexicon_fst.pl requires a probabilistic version, so we just leave it as it is.

#This is a command line perl call that adds a probability of 1.0 to the lexicon file. It reads in
#the lines from lexicon file, and adds 1.0 in between the word and characters.
#eg: SAFI 1.0 S A F I.
#Store the results in lexiconp.txt file in the temp directory
perl -ape 's/(\S+\s+)(.+)/${1}1.0\t$2/;' < $srcdir/lexicon.txt > $tmpdir/lexiconp.txt || exit 1;

# Add disambiguation symbols to the lexicon. This is necessary for determinizing the composition of L.fst and G.fst.
# Without these symbols, determinization will fail.
# default first disambiguation is #1

#this script will add disambiguation phones(characters) at the end of the character sequence of our
#lexicon file. This is done inorder for determinization of our WFST. If the phone sequence is present
#more than once, then add #1. If the "same" full sequence occurs more than once, then #2, #3 ....
#i.e, for our "classes" lexicons, we used 一 to represent the phone sequence. But this is repeated already,
#so, we use #2, #3, and ... for this.
ndisambig=`utils/fst/add_lex_disambig.pl $tmpdir/lexiconp.txt $tmpdir/lexiconp_disambig.txt`
# add #0 (#0 reserved for symbol in grammar).
ndisambig=$[$ndisambig+1];


#Writing all the disambiguation symbols to the disambig.list file in the tmp directory.
( for n in `seq 0 $ndisambig`; do echo '#'$n; done ) > $tmpdir/disambig.list

# Get the full list of CTC tokens used in FST. These tokens include <eps>, the blank <blk>,
# the actual model unit, and the disambiguation symbols.

#Creating a file with all possible tokens along with the <eps> token, the disambiguation symbols
#Storing them in the tokens.txt file in the lang directory along with an ID for each.
cat $srcdir/units.txt | awk '{print $1}' > $tmpdir/units.list
(echo '<eps>';) | cat - $tmpdir/units.list $tmpdir/disambig.list | awk '{print $1 " " (NR-1)}' > $dir/tokens.txt

# ctc_token_fst_corrected is too big and too slow for character based chinese modeling,
# so here just use simple ctc_token_fst

#This line is used to create a token FST (T). First the python script outputs a "txt file" kindof thing
#on the standard output that denotes all the transitions. Then this is consumed by the fstcompile command
#to get the fst file which is further sent to fstarcsort which finally gives us T.fst file.
utils/fst/ctc_token_fst.py --token_file $dir/tokens.txt | \
  fstcompile --isymbols=$dir/tokens.txt --osymbols=$dir/tokens.txt --keep_isymbols=false --keep_osymbols=false | \
  fstarcsort --sort_type=olabel > $dir/T.fst || exit 1;

# Encode the words with indices. Will be used in lexicon and language model FST compiling.

#This line is used to assign indices to all the words in the lexicon file. Storing the new outputs
#to the words.txt file in the lang directory.
cat $tmpdir/lexiconp.txt | awk '{print $1}' | sort | awk '
  BEGIN {
    print "<eps> 0";
  }
  {
    printf("%s %d\n", $1, NR);
  }
  END {
    printf("#0 %d\n", NR+1);
    printf("<s> %d\n", NR+2);
    printf("</s> %d\n", NR+3);
    printf("ROOT %d\n", NR+4);
  }' > $dir/words.txt || exit 1;

# Now compile the lexicon FST. Depending on the size of your lexicon, it may take some time.
token_disambig_symbol=`grep \#0 $dir/tokens.txt | awk '{print $2}'`
word_disambig_symbol=`grep \#0 $dir/words.txt | awk '{print $2}'`


#This line is used to create a lexicon FST (L). The first perl script takes in the disambiguated lexicon file
#along with the disambiguation symbols and prints all the transitions where, for each word, the first transition will 
#output the word and the remaining transitions will output epsilon. We take in the pronounciation probabilities
#and convert them to negative log semiring to treat it as the transition probabilities/cost.
#This standard output is then taken by the fstcompile and others to create the final L.fst file.
utils/fst/make_lexicon_fst.pl --pron-probs $tmpdir/lexiconp_disambig.txt 0 "sil" '#'$ndisambig | \
  fstcompile --isymbols=$dir/tokens.txt --osymbols=$dir/words.txt \
  --keep_isymbols=false --keep_osymbols=false |   \
  fstaddselfloops  "echo $token_disambig_symbol |" "echo $word_disambig_symbol |" | \
  fstarcsort --sort_type=olabel > $dir/L.fst || exit 1;

echo "Lexicon and Token FSTs compiling succeeded"
