{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ExtendedDefaultRules #-}


import Database.SQLite.Simple
import Lucid
import Web.Scotty

import Data.Default (def)

import Control.Monad.IO.Class
import Control.Monad

import Data.Text (Text)

import Data.Binary (decodeFileOrFail, encodeFile)

import System.Exit
import System.Environment
import System.Directory
import System.IO (hPutStrLn, stderr)
import System.IO.Error
import System.FilePath ( (</>) )

import Data.Aeson.Types

import qualified Text.MMark as MMark

import Data.Maybe

import Jassbot.Search
import Jassbot.DB
import Jassbot.Signature

import qualified Jass.Ast

instance ToJSON Jass.Ast.Constant
instance ToJSON Native
instance ToJSON Signature

annotation :: Text -> Text -> Text -> Html ()
annotation line name v =
  case name of
    "async" -> do
        b_ "async"
        ": "
        p_ "This function is asynchronous. The values it returns are not guaranteed to be the same for each player. If you attempt to use it in an synchronous manner it may cause a desync."

    "pure" -> do
        b_ "pure" 
        ": "
        p_ "This function is pure. For the same values passed to it, it will always return the same value."
    "source-file" -> do
        b_ "Source" 
        ": "
        a_ [href_ $ "https://github.com/lep/jassdoc/blob/master/" <> v <> "#L" <> line] $ toHtml v
    "source-code" -> do
        b_ "Source code" 
        ": "
        p_ $ pre_ $ toHtml v
    "return-type" -> do
        b_ "return type" 
        ": "
        code_ $ toHtml v
    "event" -> do
        b_ "event" 
        ": "
        code_ $ toHtml v
    _ -> do
        b_ $ toHtml name 
        p_ $ markdown $ Just v

markdown x = fromMaybe mempty $ do
    doc <- x
    case MMark.parse "" doc of
        Left _ -> Nothing
        Right f -> pure $ MMark.render f

--page :: Text -> Html ()
--docPage :: Html () -> Html ()
docPage :: Text -> Text -> [(Text, Text, Maybe Text)] -> [(Text, Text)] -> Html ()
docPage fn line params anns  = do
    html_ $ do
        head_ $ do
            meta_ [charset_ "utf-8"]
            title_ $ toHtml fn
            link_ [rel_ "stylesheet", type_ "text/css", href_ "/hl.css"]
            link_ [rel_ "stylesheet", type_ "text/css", href_ "/style.css"]
            script_ [src_ "/test.js"] ("" :: Text)

        body_ [onload_ "hl()"] $ do
            div_ [id_ "main"] $ do
                div_ [id_ "parameters"] $ do
                    when (not $ null params) $ do
                        b_ "Parameters"
                        ": "
                        table_ $ do
                            forM_ params $ \(name, ty, doc) -> do
                                tr_ $ do
                                    td_ $ toHtml name
                                    td_ $ code_ $ toHtml ty
                                    td_ $ markdown doc
                
                forM_ anns $ \(name, doc) -> do
                    div_ $ annotation line name doc

welcomePage :: Html ()
welcomePage = do
    h1_ "Welcome to jassbot"
    "Jassbot is a JASS2 API search engine, which allows you to search"
    " the JASS2 standard API (common.j and Blizzard.j) by either function"
    " name, or by approximate type signature."

    p_ [id_ "example"] $ do
        "Example searches:"
        br_ []
        a_ [href_ "/search?query=TRVE"] "TRVE"
        br_ []
        a_ [href_ "/search?query=takes handle returns integer"] "takes handle returns integer"
        br_ []
        a_ [href_ "/search?query=Unit takes unit, integer, integer real"] "Unit takes unit, integer, integer real"

        br_ []
        a_ [href_ "/search?query=returns widget"] "returns widget"

    "This project is ofcourse heavily inspired by the great "
    a_ [href_ "https://hoogle.haskell.org"] "Hoogle"
    "."
    " Its source code and data is free. You can find the command line interface for jassbot "
    a_ [href_ "https://github.com/lep/jassbot"] "here"

    " and the source for this webinterface "
    a_ [href_ "https://github.com/lep/jassdoc-browser"] "here"
    ". The data can be found "
    a_ [href_ "https://github.com/lep/jassdoc"] "here"
    "."

searchPage :: Html () -> Html ()
searchPage x = do
    html_ $ do
        head_ $ do
            meta_ [charset_ "utf-8"]
            title_ "Search"
            link_ [rel_ "stylesheet", type_ "text/css", href_ "/hl.css"]
            link_ [rel_ "stylesheet", type_ "text/css", href_ "/style.css"]
            script_ [src_ "/test.js"] ("" :: Text)
            script_ [src_ "/preview.js"] ("" :: Text)

        body_ [onload_ "hl();setup()"] $ do
            div_ [id_ "searchbox"] $ do
                form_ [id_ "searchinput", action_ "/search", method_ "get"] $ do
                    a_ [id_ "home", href_ "/search"] $ toHtmlRaw  "&lambda;"
                    input_ [id_ "search", name_ "query", type_ "text", placeholder_ "Search for..."]
                    input_ [type_ "submit", value_ "Search"]

            div_ [id_ "main"] $ do
                div_ [id_ "results"] $ do
                    x
            
resultPage :: [(Double, Signature)] -> Html ()
resultPage x = do
    forM_ (map snd x) $ \sig -> do
        div_ [class_ "result"] $
            code_ $ toHtml $ pretty sig

--searchPage

-- :: [(String, String, Maybe String)]
paramQuery :: Query
paramQuery = 
     "select Ty.param, Ty.value, Doc.value \
     \ from \
     \ ( select Value, param \
     \   from params_extra \
     \   where anname == 'param_order' \
     \      and fnname == :fnname \
     \ ) as Ord \

     \ inner join \
     \ ( select param, value \
     \   from params_extra \
     \   where anname == 'param_type' \
     \      and fnname == :fnname \
     \ ) as Ty on Ty.param == Ord.param \

     \ left outer join \
     \ ( select param, value from parameters \
     \   where fnname == :fnname \
     \ ) as Doc on Doc.param == Ord.param \

     \ order by Ord.value"
    

-- :: [(String, String)]
annQuery :: Query
annQuery =
    " select anname, value \
    \ from annotations \
    \ where fnname == :fnname \
    \   and anname not in ('start-line', 'end-line') \
    \ order by anname "


-- :: [Only String]
lineQuery :: Query
lineQuery =
    " select value \
    \ from annotations \
    \ where fnname == :fnname \
    \   and anname == 'start-line' "

getDbPath :: Maybe String -> IO String
getDbPath x =
  case x of
    Just datadir -> return datadir
    Nothing -> getXdgDirectory XdgData "jassbot"

readDb :: Maybe String -> IO DB
readDb p = do
    datadir <- getDbPath p
    x <- tryIOError (decodeFileOrFail $ datadir </> "jassbot.db")
    case x of
        Left ex -> do
            hPutStrLn stderr $ unwords ["Could not open database. Have you run init yet?", show ex]
            exitWith $ ExitFailure 1
        Right x' ->
          case x' of
            Right x' -> return x'
            Left (_, msg) -> do
                hPutStrLn stderr $ unwords ["Could not open database. Have you run init yet?", msg]
                exitWith $ ExitFailure 1

main = do
    conn <- open "jass.db"
    --path <- Just . head <$> getArgs
    db <- readDb Nothing
    scottyOpts def { verbose = 0 } $ do
    --scotty 3000 $ do
        get "/doc/:fn" $ do
            fn <- param "fn"
            [Only line] <- liftIO $ queryNamed conn lineQuery [":fnname" := fn ]
            annotations <- liftIO $ queryNamed conn annQuery [":fnname" := fn ]
            params <- liftIO $ queryNamed conn paramQuery [":fnname" := fn]

            html $ renderText $ docPage fn line params annotations

        get "/search" $ do
            q <- param "query" `rescue` const next
            let r = take 20 $ search db q 0.4
            html $ renderText $ searchPage $ resultPage r

        get "/search" $ do
            html $ renderText $ searchPage welcomePage

        get "/api/:query" $ do
            q <- param "query"
            let r = take 20 $ search db q 0.4
            json r


        get "/hl.css" $ file "public/hl.css"
        get "/style.css" $ file "public/style.css"
        get "/test.js" $ file "public/test.js"
        get "/preview.js" $ file "public/preview.js"

        get "/favicon.ico" $ file "public/favicon.ico"
        
