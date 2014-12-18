{-# LANGUAGE ExistentialQuantification, FlexibleContexts, RankNTypes #-}
{- |

   The Forth interpreter state and embedding it a monad transformer.

-}

module Language.Forth.Machine (FM, FState(..), CV, module Control.Monad.Trans.State,
                               Compiler(..), Defining(..), DefiningWrapper(..)) where

import Control.Monad
import Control.Monad.Trans.State hiding (state)
import Data.IntMap (IntMap)
import Data.Map (Map)
import qualified Data.Vector.Storable.ByteString.Char8 as V (ByteString)
import Data.ByteString.Lazy.Char8 (ByteString)
import Data.Vector (Vector)
import System.Console.Haskeline
import Language.Forth.Interpreter.Address
import Language.Forth.Interpreter.DataField
import Language.Forth.CellVal
import Language.Forth.Dictionary
import Language.Forth.Primitive
import Language.Forth.Target
import Language.Forth.Word
import Translator.Assembler.Generate (IM)
import Translator.Assembler.InstructionSet
import Translator.Expression

-- Interpreter monad
type FM t = StateT (FState t) (InputT IO)

-- Simpler way of specifying a cell value
type CV t = CellVal (FM t ())

-- | Interpreter state.
data FState t = FState
  { stack  :: [CV t]               -- ^ Data stack
  , rstack :: [CV t]               -- ^ Return stack
  , ip     :: [FM t ()]            -- ^ Interpretive pointer
  , target :: Target
  , dict   :: Dictionary (FM t ()) -- ^ Dictionary of Forth words for interpreter
  , variables :: IntMap (DataField (FM t ()))
  , oldHandles :: [WordId]                 -- ^ Unused handles after reading source files
  , stringLiterals :: Map V.ByteString Addr
  , compilerFuns :: Compiler t (Defining (FM t ()))
  , defining :: Maybe (Defining (FM t ()))   -- ^ Collector when compiling
  , targetDict :: forall t1. InstructionSet t1 => Maybe (Dictionary (IM t1)) -- ^ Cross compiler dictionary
  }

-- | The defining state for the interpreter.
--   We collect words into a Vector together with information about locations
--   to change when we have collected all.
data Defining a = Defining {
    compileList :: Vector (DefiningWrapper a)
  , patchList :: [(Int, Int)]               -- ^ (loc, dest) list to patch
  , defineFinalizer :: [a] -> a
  , definingWord :: ForthWord a
  }
  | TargetDefining {
    tcompileList :: Vector Expr
}

-- | Wrapper for words being compile. This is used to keep track of branches
--   that are waiting to have their address fixed.
data DefiningWrapper a = WrapA a | WrapB ([a] -> a) | WrapRecurse

-- | Compiler primitives. This record keeps track of compiler primitives,
--   and is meant to be replaced when cross compiling to some other target.
data Compiler t d = Compiler {
    compile :: CV t -> d -> d
    -- ^ Compile a cell value to a colon definition
  , litComma :: CV t -> d -> d
    -- ^ Compile a cell value from the stack
  , compileBranch :: CellVal t -> d -> d
    -- ^ Compile a unconditional branch instruction, not used by the interpreter
  , compileBranch0 :: CellVal t -> d -> d
    -- ^ Compile a conditional branch instruction, not used by the interpreter
  , recurse :: d -> d
    -- ^ Compile a recursive call back to the start of current definition
  , addCompiledWord :: d -> FState t -> FState t
    -- ^ Add compiled word to active dictionary in the Forth state
  }
