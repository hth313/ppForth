{-# LANGUAGE  RankNTypes #-}
{-
  This file is part of CalcForth.
  Copyright Håkan Thörngren 2011

  Forth parser.

  This is a simplified Forth parser inteded to parse the Core set of variables and
  colon definitions. It will not handle everything a real Forth parser will allow
  you to and does not behave strictly as Forth does.

  When the Core set has been read, it is meant to be used to process further
  Forth code, which will allow the full blown rich set of Forth behavior for all
  extension sets.

-}

module Forth.Parser (parseForth) where

import Forth.Machine
import Text.Parsec.Prim
import qualified Text.Parsec.Token as P
import Text.Parsec.Language
import Text.Parsec.Char
import Text.Parsec.Combinator
import Text.Parsec.Error

--type Parser cell = ParsecT String () (StateT (Machine cell) IO)
type Parser a = forall cell.ParsecT String () (StateT (Machine cell) IO) a

-- | The parser is based on Parsec and run as a Monad tranformer with the Forth Machine
--   monad as the inner monad.
parseForth :: String -> String -> StateT (Machine cell) IO (Either ParseError ())
parseForth screenName text = runParserT topLevel () screenName text

lexer :: P.GenTokenParser String () (StateT (Machine cell) IO)
lexer  = P.makeTokenParser (P.LanguageDef { P.commentStart = "(",
                                            P.commentEnd = ")",
                                            P.commentLine = "\\",
                                            P.nestedComments = False,
                                            P.reservedNames = [":", ";", "CREATE",
                                                               "VARIABLE", "CONSTANT" ],
                                            P.identStart = wordChar,
                                            P.identLetter = wordChar,
                                            P.opStart = never,
                                            P.opLetter = never,
                                            P.reservedOpNames = [],
                                            P.caseSensitive = True } )
identifier :: Parser String
identifier = P.identifier lexer

reserved :: String -> Parser ()
reserved name = P.reserved lexer name

-- Most characters are accepted in a Forth word, but it can be a bit more restrictive
-- than this
wordChar, never :: Parser Char
wordChar = noneOf " \t\n"
never = satisfy (const False)

-- Parse a top level construct
topLevel :: Parser ()
topLevel = many definition >> eof

definition :: Parser ()
definition = colonDef <|> create

colonDef :: Parser ()
colonDef = do
  reserved ":"
  name <- identifier
  body <- manyTill identifier (reserved ";")
  body' <- lift $ mapM wordFromName body
  lift $ addWord (ForthWord name False (Just $ Code Nothing Nothing (Just body')))
  return ()

create :: Parser ()
create = do
  reserved "CREATE"
  name <- identifier
  return ()
