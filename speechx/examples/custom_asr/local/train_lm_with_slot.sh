#!/bin/bash

# To be run from one directory above this script.
. ./path.sh
src=ds2_graph_with_slot  #in the exp folder
text=$src/train_text  #This file is the main text with slots used to train the LM
lexicon=$src/local/dict/lexicon.txt  #This file is the preprocessed lexicon file

dir=$src/local/lm
mkdir -p $dir


#Check if the text files and lexicon files are present or not
for f in "$text" "$lexicon"; do
  [ ! -f $x ] && echo "$0: No such file $f" && exit 1;
done

# Check SRILM tools
if ! which ngram-count > /dev/null; then
  pushd $MAIN_ROOT/tools
  make srilm.done
  popd
fi

# This script takes no arguments.  It assumes you have already run
# It takes as input the files
# data/local/lm/text
# data/local/dict/lexicon.txt


cleantext=$dir/text.no_oov

#In this line, we are taking our original text file (i.e., $text) and checking whether
#each word in that text file is present in our lexicon or not. If it is not present, then we
#add <spoken_noise> in its place. So, in our case, since the first word of all sentences in
#the text file is a random ID or string, we add the <spoken_noise> class before each sentence.
#Output of this stored in text.no_oov file. 
# In essence, we are cleaning our text data to remove the OOV words so that it becomes
#better associated with our ASR model. (Here $seen is an "associative array")
cat $text | awk -v lex=$lexicon 'BEGIN{while((getline<lex) >0){ seen[$1]=1; } }
  {for(n=1; n<=NF;n++) {  if (seen[$n]) { printf("%s ", $n); } else {printf("<SPOKEN_NOISE> ");} } printf("\n");}' \
  > $cleantext || exit 1;

#In this line, we are collecting the word counts. First we print a file of all words sequentially
#even repeated words. Then we sort those words. Then using the uniq -c command, we collect how many times
#each word was repeated. Then we sort those counts in reverse order to get the word counts.
# here starting from n=2 because n=1 is always <spoken noise> in our case and we want to ignore it.
cat $cleantext | awk '{for(n=2;n<=NF;n++) print $n; }' | sort | uniq -c | \
   sort -nr > $dir/word.counts || exit 1;



# Get counts from acoustic training transcripts, and add  one-count
# for each word in the "lexicon" (but not silence, we don't want it
# in the LM-- we'll add it optionally later).



#In this line, we are adding 1 to all the previous counts that we got
#except for the SIL token. Also, adding the remaining words (that were 
#not present in our text but present in our lexicon) with count 1. This is
#done to somehow ensure that OOV words are accounted for in our Language
#Model. (Thats why this unigram_counts file is much bigger than words_counts)
cat $cleantext | awk '{for(n=2;n<=NF;n++) print $n; }' | \
  cat - <(grep -w -v '!SIL' $lexicon | awk '{print $1}') | \
   sort | uniq -c | sort -nr > $dir/unigram.counts || exit 1;



# filter the words which are not in the text


#In this line, we get the word list by removing all the words that were
#having counts 
cat $dir/unigram.counts | awk '$1>1{print $0}' | awk '{print $2}' | cat - <(echo "<s>"; echo "</s>" ) > $dir/wordlist

# kaldi_lm results

#In this line, we are removing the last space present in the text.n_oov
#file  and replacing it by "".
mkdir -p $dir
cat $cleantext | awk '{for(n=2;n<=NF;n++){ printf $n; if(n<NF) printf " "; else print ""; }}' > $dir/train


#Calling the SRILM training script with our train data, 3grams, 
ngram-count -text $dir/train -order 3 -limit-vocab -vocab $dir/wordlist -unk \
  -map-unk "<UNK>" -gt3max 0 -gt2max 0 -gt1max 0 -lm $dir/lm.arpa

#ngram-count -text $dir/train -order 3 -limit-vocab -vocab $dir/wordlist -unk \
#  -map-unk "<UNK>" -lm $dir/lm2.arpa