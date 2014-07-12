{-# LANGUAGE OverloadedStrings #-}
{- |

   Build the dictionary.

-}

module Language.Forth.Dictionary (newDictionary, Dictionary(..),
                                  sourceWId, stateWId, toInWId,
                                  inputBufferWId, inputLineWId, tregWid,
                                  inputLineLengthWId, wordBufferWId, sourceIDWid,
                                  addWord, makeImmediate, setLatestImmediate) where

import Control.Monad
import Control.Monad.Trans.Class
import Control.Monad.Trans.State hiding (state)
import Data.Vector.Storable.ByteString.Char8 (ByteString)
import Language.Forth.Interpreter.Address
import Language.Forth.Interpreter.CellMemory
import Language.Forth.Interpreter.DataField
import Language.Forth.CellVal
import Language.Forth.Primitive
import Language.Forth.Target
import Language.Forth.Word
import Prelude hiding (drop, or, and)

data Dictionary a = Dictionary
  { wids :: [WordId]
  , latest :: LinkField a
  }

-- Word identities are used to identify a particular word in a unique way.
-- They are used to find mutable datafields, which are stored separately in
-- the Forth state of the interpreter.
-- Some words (typically variables) that are needed early get theie word
-- identity preallocated here and we use the tail for the rest of words.
(sourceWId : stateWId : toInWId : inputBufferWId : inputLineWId :
 inputLineLengthWId : wordBufferWId : sourceIDWid : tregWid : wordsIds) = map WordId [0..]

-- Create a new basic dictionary.
newDictionary :: Primitive c a => State (Dictionary a) WordId -> Dictionary a
newDictionary extras = execState build (Dictionary wordsIds Nothing)
  where
    build = do
      addWord "EXIT"  semi
      addWord "EVALUATE" evaluate
      addWord "EXECUTE" execute
      addWord "SWAP" swap
      addWord "DROP" drop
      addWord "OVER" over
      addWord "DUP"  dup
      addWord "ROT"  rot
      addWord "R>"   rto
      addWord ">R"   tor
      addWord "R@"   rfetch
      addWord "+"    plus
      addWord "-"    minus
      addWord "/"    slash
      addWord "AND"  and
      addWord "OR"   or
      addWord "XOR"  xor
      addWord "FALSE" false
      addWord "TRUE" true
      addWord "0="   zerop
      addWord "0<"   lt0
      addWord "!"    store
      addWord "C!"   cstore
      addWord "@"    fetch
      addWord "C@"   cfetch
      addWord "STATE" state
      addWord "SOURCE-ID" sourceId
      addWord ">IN" toIn
      addWord "#INBUF" inputBuffer
      addWord "INPUT-LINE" inputLine
      addWord "#INPUT-LINE" inputLineLength
      addWord "SOURCE-ID" sourceID
      addWord "CONSTANT" constant
      addWord "UM*" umstar
      extras

addWord name doer =
  StateT $ \s ->
    let i:is = wids s
    in  return (i, s { wids = is,
                       latest = Just $ ForthWord name False (latest s) i doer })

makeImmediate :: State (Dictionary a)  ()
makeImmediate = modify setLatestImmediate

setLatestImmediate s = s { latest = fmap imm (latest s) }
  where imm word = word { immediateFlag = True }
