module Unison.Term where

import Array
import Array (Array)
import Dict
import Dict (Dict)
import Json
import Set
import Set (Set)
import Graphics.Element as Element
import Graphics.Input (Handle, hoverable)
import Text(..)
import Unison.Styles as Styles
import Unison.Hash (Hash)
import Unison.Hash as H
import Unison.Jsonify as J
import Unison.Jsonify (Jsonify)
import Unison.Metadata as Metadata
import Unison.Metadata (Metadata, Fixity)
import Unison.Parser as P
import Unison.Parser (Parser)
import Unison.Path (..)
import Unison.Var (I)
import Unison.Var as V
import Unison.Type as T

data Literal
  = Number Float
  | String String
  | Vector (Array Term)

data Term
  = Var I
  | Lit Literal
  | Con Hash
  | Ref Hash
  | App Term Term
  | Ann Term T.Type
  | Lam I Term

render : Term -- term to render
      -> { handle         : Handle (Maybe (Hash, Path))
         , key            : Hash
         , highlighted    : Set Path
         , availableWidth : Int
         , metadata       : Hash -> Metadata }
      -> Element
render expr env =
  let
    md = env.metadata env.key
    go : Bool -> Int -> Int -> { path : Path, term : Term } -> Element
    go allowBreak ambientPrec level cur =
      case cur.term of
        Var n -> hoverable env.handle (msg cur.path) (code (Metadata.resolveLocal md cur.path n).name)
        Ref h -> hoverable env.handle (msg cur.path) (code (Metadata.firstName h (env.metadata h)))
        Con h -> hoverable env.handle (msg cur.path) (code (Metadata.firstName h (env.metadata h)))
        Lit (Number n) -> hoverable env.handle (msg cur.path) (code (show n))
        Lit (String s) -> hoverable env.handle (msg cur.path) (code s)
        _ -> case break md cur.path cur.term of
          Prefix f args ->
            let fE = go False 9 level f
                lines = fE :: map (go False 10 level) args
                spaceL = spaces level
                unbroken = flow right [
                  spaceL,
                  paren (ambientPrec > 9) cur.path (flow right (intersperse space lines))
                ]
            in if not allowBreak || widthOf unbroken < env.availableWidth
               then unbroken
               else flow down <| indent level fE :: map (go True 10 (level + 1)) args
          Operators leftAssoc prec hd tl ->
            let f (op,r) l = flow right [ l, space, go False 10 level op, space, go False rprec level r ]
                unbroken = flow right [spaceL, foldl f (go False lprec level hd) tl]
                lprec = if leftAssoc then prec else 1+prec
                rprec = if leftAssoc then 1+prec else prec
                spaceL = spaces level
                bf (op,r) l = flow down [
                  l,
                  flow right [spaceL, go False 10 level op, space, go False rprec level r ]
                ]
            in if not allowBreak || widthOf unbroken < env.availableWidth
               then unbroken
               else let h = hoverable env.handle (msg cur.path) (spaces 2)
                    in foldl bf (flow right [spaceL, h, go False lprec level hd]) tl
          _ -> todo

    code s = leftAligned (style Styles.code (toText s))
    msg path b = if b then Just (env.key, path) else Nothing

    paren : Bool -> Path -> Element -> Element
    paren parenthesize path e =
      if parenthesize
      then let (opening, closing) = (code "(", code ")")
               topOpen = container (widthOf opening) (heightOf e) topLeft (code "(")
                            |> hoverable env.handle (msg path)

               bottomClose = container (widthOf closing) (heightOf e) bottomLeft (code ")")
                            |> hoverable env.handle (msg path)
           in flow right [topOpen, e, bottomClose]
      else e

    space = code " "
    spaces n = code (String.padLeft (n*2) ' ' "")

    indent : Int -> Element -> Element
    indent level e = flow right [spaces level, e]

    -- prec : Term -> Int
    -- prec (Hash)

  in todo

data Break a
  = Prefix a [a]          -- `Prefix f [x,y,z] == f x y z`
  | Operators Bool Int a [(a,a)] -- `Operators False x [(+,y), (+,z)] == (x + y) + z`
                                 -- `Operators True x [(^,y), (^,z)] == x ^ (y ^ z)`
  | Bracketed [a]         -- `Bracketed [x,y,z] == [x,y,z]`
  | Lambda [a] a          -- `Lambda [x,y,z] e == x -> y -> z -> e`

break : Metadata -> Path -> Term -> Break { path : Path, term : Term }
break md path expr = todo

todo : a
todo = todo

parseLiteral : Parser Literal
parseLiteral = P.union' <| \t ->
  if | t == "Number" -> P.map Number P.number
     | t == "String" -> P.map String P.string
     | t == "Vector" -> P.map (Vector . Array.fromList) (P.array parseTerm)

jsonifyLiteral l = case l of
  Number n -> J.tag' "Number" J.number n
  String s -> J.tag' "String" J.string s
  Vector es -> J.tag' "Vector" (J.contramap Array.toList (J.array jsonifyTerm)) es

parseTerm : Parser Term
parseTerm = P.union' <| \t ->
  if | t == "Var" -> P.map Var V.parse
     | t == "Lit" -> P.map Lit parseLiteral
     | t == "Con" -> P.map Con H.parse
     | t == "Ref" -> P.map Ref H.parse
     | t == "App" -> P.lift2 App parseTerm parseTerm
     | t == "Ann" -> P.lift2 Ann parseTerm T.parseType
     | t == "Lam" -> P.lift2 Lam V.parse parseTerm

jsonifyTerm : Jsonify Term
jsonifyTerm e = case e of
  Var v -> J.tag' "Var" V.jsonify v
  Lit l -> J.tag' "Lit" jsonifyLiteral l
  Con h -> J.tag' "Con" H.jsonify h
  Ref h -> J.tag' "Ref" H.jsonify h
  App f x -> J.tag' "App" (J.array jsonifyTerm) [f, x]
  Ann e t -> J.tag' "Ann" (J.tuple2 jsonifyTerm T.jsonifyType) (e, t)
  Lam n body -> J.tag' "Lam" (J.tuple2 V.jsonify jsonifyTerm) (n, body)
