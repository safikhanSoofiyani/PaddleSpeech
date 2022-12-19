#!/usr/bin/env python3
import argparse


def main(args):
    # load vocab file
    # line: token
    unit_table = set()
    
    # Storing each token in a set to create a unique token set
    with open(args.unit_file, 'r') as fin:
        for line in fin:
            unit = line.strip()
            unit_table.add(unit)

    #Function that checks whether the current word has any OOV tokens
    def contain_oov(units):
        """token not in vocab

        Args:
            units (str): token

        Returns:
            bool: True if token not in vocab, else False if all
                  tokens are in vocabulary (then it doesnt have OOV).
        """
        for unit in units:
            if unit not in unit_table:
                return True
        return False


    ## This is in case we are working in the BPE domain
    # load spm model, for English
    bpemode = args.bpemodel
    if bpemode:
        import sentencepiece as spm
        sp = spm.SentencePieceProcessor()
        sp.Load(sys.bpemodel)

    # used to filter polyphone and invalid word
    lexicon_table = set() #this lexicon table is created to ensure a word has only one mapping to characters
    in_n = 0  # in lexicon word count
    out_n = 0  # out lexicon word count
    
    #Opening (in_lexicon) lexicon file in read mode and the (out_lexicon) in write mode
    with open(args.in_lexicon, 'r') as fin, \
            open(args.out_lexicon, 'w') as fout:
            
        #For each line (i.e., each word w o r d)
        for line in fin:
            word = line.split()[0]
            in_n += 1

            if word == 'SIL' and not bpemode:  # `sil` might be a valid piece in bpemodel
                # filter 'SIL' for mandarin, keep it in English
                continue
            elif word == '<SPOKEN_NOISE>':
                # filter <SPOKEN_NOISE>
                continue
            else:
                # each word only has one pronunciation for e2e system
                if word in lexicon_table:
                    #If word has already been encountered, then ignore
                    #inorder to maintain a unique mapping between word and chars
                    continue

                #Do this if we are working in BPE level
                if bpemode:
                    # for english
                    pieces = sp.EncodeAsPieces(word)
                    if contain_oov(pieces):
                        print('Ignoring words {}, which contains oov unit'.
                              format(''.join(word).strip('▁')))
                        continue

                    # word is piece list, which not have <unk> piece, filter out by `contain_oov(pieces)`
                    chars = ' '.join(
                        [p if p in unit_table else '<unk>' for p in pieces])
                        
                #If we are working in character domain
                else:
                    # ignore words with OOV
                    if contain_oov(word):
                        print('Ignoring words {}, which contains oov unit'.
                              format(word))
                        continue

                    # Optional, append ▁ in front of english word
                    # we assume the model unit of our e2e system is char now.
                    if word.encode('utf8').isalpha() and '▁' in unit_table:
                        word = '▁' + word
                    
                    #Collecting the characters (by using space in between)
                    chars = ' '.join(word)  # word is a char list
                #Writing the word - chars pair to the output lexicon file
                fout.write('{} {}\n'.format(word, chars))
                #adding the word to the lexicon table to maintain uniqueness.
                lexicon_table.add(word)
                out_n += 1

    print(
        f"Filter lexicon by unit table: filter out {in_n - out_n}, {out_n}/{in_n}"
    )


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='FST: preprae e2e(char/spm) dict')
    parser.add_argument(
        '--unit_file',
        required=True,
        help='e2e model unit file(lang_char.txt/vocab.txt). line: char/spm_pices'
    )
    parser.add_argument(
        '--in_lexicon',
        required=True,
        help='raw lexicon file. line: word ph0 ... phn')
    parser.add_argument(
        '--out_lexicon',
        required=True,
        help='output lexicon file. line: word char0 ... charn')
    parser.add_argument('--bpemodel', default=None, help='bpemodel')

    args = parser.parse_args()
    print(args)

    main(args)
