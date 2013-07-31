{-# LANGUAGE DeriveDataTypeable, OverloadedStrings #-}
{-
  This file is part of Planet Pluto Forth.
  Copyright Håkan Thörngren 2011-2013

  Forth compiler and interpreter basic definitions.

-}

module Forth.Machine (MachineM, ForthLambda, Machine(..), push, pop, pushAdr,
                      ForthException(..),
                      ForthWord(..), StateT(..), emptyStack, abortWith,
                      initialState, evalStateT, execute,
                      create, makeImmediate, smudge,
                      addNative, addFixed, addVar, putField,
                      wordBufferId,
                      inputBufferId, inputBufferPtrId, inputBufferLengthId,
                      stateId, sourceId, toInId,
                      wordIdExecute, wordLookup,
                      doColon, doVar,
                      withTempBuffer,
                      compile) where

import Control.Applicative
import Control.Exception
import Control.Monad.State.Lazy
import qualified Data.Vector as V
import Data.Vector.Storable.ByteString (ByteString)
import qualified Data.Vector.Storable.ByteString as B
import qualified Data.Vector.Storable.ByteString.Char8 as C
import Data.Maybe
import Data.Typeable
import Data.Word
import Data.IntMap (IntMap)
import qualified Data.IntMap as IntMap
import Forth.Address
import Forth.CellMemory
import Forth.DataField
import Forth.Target
import Forth.Word
import Forth.WordId
import Forth.Types

type MachineM cell = StateT (Machine cell) IO

-- The Forth state
data Machine cell = Machine { -- The Forth stacks
                              stack, rstack :: [Lit cell],
                              dictionaryHead :: LinkField cell,
                              defining :: LinkField cell,  -- ^ word being defined
                              ip :: Maybe (IP cell),
                              target :: Target cell,
                              -- Sequence of identies to allocate from
                              keys :: [WordId],
                              -- Data fields for words that need it. This need
                              -- to be modifiable as we mimic data ram. We
                              -- rely on that the underlaying identity of
                              -- a WordId is an Int here.
                              variables :: IntMap (DataField cell),
                              wordMap :: IntMap (ForthWord cell),
                              oldHandles :: [WordId]
    }

-- A Forth native lambda should obey this signature
type ForthLambda cell = MachineM cell ()

data ForthException = ForthException String deriving Typeable

instance Exception ForthException
instance Show ForthException where
    show (ForthException text) = text

-- | Internal words that does not need to be redefinable can share
--   this identity.
pseudoId = 0

-- | WordId used for special purposes
wordBufferId = 1 :: Int     -- ^ Transient area for WORD
inputBufferId = 2 :: Int    -- ^ Input buffer (console)
inputBufferPtrId = 3 :: Int  -- ^ Variable that point out current input buffer
inputBufferLengthId = 4 :: Int    -- ^ Input buffer length
stateId = 5 :: Int          -- ^ Compile state
sourceId = 6 :: Int         -- ^ SOURCE-ID
toInId = 7 :: Int           -- ^ >IN

-- The first dynamic word identity
firstId = 8

-- | Lookup a word from its identity number
wordIdExecute wid = do
  w <- wordLookup wid
  case w of
    Just w -> call w

wordLookup :: WordId -> MachineM cell (Maybe (ForthWord cell))
wordLookup wid = gets $ \s -> IntMap.lookup wid (wordMap s)

call word = doer word word

-- | Top level item on stack should be an execution token that is invoked.
execute = pop >>= executeXT

executeXT (XT word) = call word
executeXT _ = abortWith "EXECUTE expects an execution token"

-- | Pop from data stack
pop :: MachineM cell (Lit cell)
pop = StateT $ \s ->
        case stack s of
          t:ts -> return (t, s { stack = ts })
          [] -> emptyStack

emptyStack = abortWith "empty stack"
abortWith = throw . ForthException

-- | Push a value on data stack
push x = modify $ \s -> s { stack = x : stack s }


-- | Push the field address of a word on stack
pushAdr wid = push $ Address (Just (Addr wid 0))


-- | Create an initial empty Forth machine state
initialState :: Target cell -> Machine cell
initialState target =
    Machine [] [] Nothing Nothing Nothing target [firstId..] IntMap.empty IntMap.empty []


create :: ByteString -> (ForthWord cell -> ForthLambda cell) -> MachineM cell ()
create name does = modify $ \s ->
    let k:ks = keys s
        word = ForthWord name False (dictionaryHead s) k does (Colon V.empty)
    in s { keys = ks,
           defining = Just word }


-- | Make word being defined visible in the dictionary
smudge :: ForthLambda cell
smudge = modify $ \s ->
    case defining s of
      Just word -> s { dictionaryHead = Just word,
                       defining = Nothing }
      otherwise -> s


makeImmediate :: ForthLambda cell
makeImmediate = modify $ \s -> s { dictionaryHead = imm <$> dictionaryHead s }
    where imm word = word { immediate = True }


-- | Add a native word to the vocabulary.
addNative :: ByteString -> ForthLambda cell -> MachineM cell ()
addNative name action = create name (const action) >> smudge


addVar name wid mval = do
  addFixed name False wid doVar
  smudge
  case mval of
    Nothing -> return ()
    Just val -> do
        t <- gets target
        let field@(DataField cm) = newDataField t wid (bytesPerCell t)
        putField wid (DataField $ writeCell val (Addr wid 0) cm)


-- | Insert the field contents of given word
putField wid field = modify $ \s -> s { variables = IntMap.insert wid field  (variables s) }


-- | Add a word with a fixed identity.
addFixed name imm wid does = modify $ \s ->
    let word = ForthWord name imm (dictionaryHead s) wid does Native
    in s { dictionaryHead = Just word,
           wordMap = IntMap.insert wid word (wordMap s) }


-- | Push the address of a variable (its data field) on stack
doVar word = push $ Address (Just (Addr (wid word) 0))


doColon word = do
  oip <- StateT $ \s ->
            let Colon cb = body word
            in return (ip s, s { rstack = Loc (ip s) : rstack s, ip = Just (IP cb 0) })
  when (isNothing oip) nextInterpreter


nextInterpreter = do
  x <- next
  case x of
    Nothing -> return ()
    Just xt -> executeXT xt >> nextInterpreter


-- | Read cell pointed out by interpretive pointer, advance pointer
next = StateT $ \s ->
    case ip s of
      Just (IP cb i) -> return (Just ((V.!) cb i), s { ip = Just (IP cb (i + 1)) })
      Nothing -> return (Nothing, s { ip = Nothing })


-- | Create a temporary word with given buffer contents. Perform action by
--   passing a reference to the buffer to it, one line at a time.
withTempBuffer action contents = do
  handle <- getHandle
  forM_ (C.lines contents) (doAction handle)
  modify $ \s -> s { variables = IntMap.delete handle (variables s) }
  releaseHandle handle
      where
        getHandle = StateT $ \s ->
             if null (oldHandles s)
             then return (head (keys s), s { keys = tail (keys s) })
             else return (head (oldHandles s), s { oldHandles = tail (oldHandles s) })

        releaseHandle handle = modify $ \s -> s { oldHandles = handle : oldHandles s }

        doAction handle line = do
          modify $ \s ->
              s { variables = IntMap.insert handle (textBuffer handle line) (variables s) }
          pushAdr handle
          push $ Val (fromIntegral $ B.length line)
          action


-- | Compile a literal into a colon body of the word being defined.
compile lit = modify $ \s ->
    case defining s of
      Just word | Colon cb <- body word ->
          s { defining = Just word { body = Colon (V.snoc cb lit)  } }
      otherwise -> abortWith "unable to compile literal value"
