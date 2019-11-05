module Test.Main where

import Prelude
import Control.Monad.Except (runExceptT)
import Data.Argonaut (encodeJson, stringify)
import Data.Array (filter)
import Data.Either (Either(..))
import Data.Foldable (find)
import Data.Lazy (Lazy, defer)
import Data.Maybe (Maybe(..))
import Data.MediaType (MediaType)
import Data.MediaType.Common (applicationJSON, textHTML)
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Aff.Class (class MonadAff)
import Foreign.Object (Object)
import Foreign.Object (insert, singleton) as FO
import Nodetrout.Error (HTTPError)
import Nodetrout.Request (Request(..))
import Nodetrout.Router (route)
import Test.Site (Default(..), messages, messageHasContent, messageHasId, messageIsUnread, resources, site)
import Test.Spec (describe, it)
import Test.Spec.Assertions (fail, shouldEqual)
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner (runSpec)

type RequestSpec =
  { method :: String
  , url :: String
  , headers :: Object String
  , readString :: Lazy (Aff (Maybe String))
  } 

defaultRequest :: RequestSpec
defaultRequest =
  { method: "GET"
  , url: "/"
  , headers: FO.singleton "accept" "*/*"
  , readString: defer $ const (pure Nothing)
  }

processRequest :: forall m. Monad m => MonadAff m => RequestSpec -> m (Either HTTPError (Tuple MediaType String))
processRequest = runExceptT <<< route site resources <<< Request

main :: Effect Unit
main = launchAff_ $ runSpec [consoleReporter] do
  describe "path segment handling" do
    it "should parse a path segment and provide it as an argument to the handler" do
      result <- processRequest $ defaultRequest { url = "/api/messages/2" }
      case result of
        Left error ->
          fail $ "Request failed unexpectedly: " <> show error
        Right (Tuple _ content) ->
          content `shouldEqual` (stringify $ encodeJson $ find (messageHasId 2) messages)
    it "should parse multiple path segments and pass them as an array to the handler" do
      result <- processRequest $ defaultRequest { url = "/api/messages/1/2" }
      case result of
        Left error ->
          fail $ "Request failed unexpectedly: " <> show error
        Right (Tuple _ content) ->
          content `shouldEqual` (stringify $ encodeJson $ filter (\m -> messageHasId 1 m || messageHasId 2 m) messages)
  describe "query string handling" do
    it "should parse a single query parameter and provide it as an argument to the handler" do
      result <- processRequest $ defaultRequest { url = "/api/messages?unread=true" }
      case result of
        Left error ->
          fail $ "Request failed unexpectedly: " <> show error
        Right (Tuple _ content) ->
          content `shouldEqual` (stringify $ encodeJson $ filter messageIsUnread messages)
    it "should parse multiple query parameters with the same label and pass them as an array to the handler" do
      result <- processRequest $ defaultRequest { url = "/api/messages?content=i&content=llo" }
      case result of
        Left error ->
          fail $ "Request failed unexpectedly: " <> show error
        Right (Tuple _ content) ->
          content
          `shouldEqual`
          (stringify $ encodeJson $ filter (\m -> messageHasContent "i" m || messageHasContent "llo" m) messages)
  describe "request body processing" do
    it "should parse the expected request body and provide it as an argument to the handler" do
      let reqBody = stringify $ encodeJson { id: 4, content: "Greetings", unread: true }
      result <- processRequest $ defaultRequest
                  { method = "POST"
                  , url = "/api/messages"
                  , readString = defer $ const (pure $ Just reqBody)
                  }
      case result of
        Left error ->
          fail $ "Request failed unexpectedly: " <> show error
        Right (Tuple _ content) -> do
          content `shouldEqual` reqBody
  describe "content negotiation" do
    it "should deliver the content in the client's preferred format when available" do
      result <- processRequest $ defaultRequest { headers = FO.insert "accept" "text/html" defaultRequest.headers }
      case result of
        Left error ->
          fail $ "Request failed unexpectedly: " <> show error
        Right (Tuple mediaType content) -> do
          mediaType `shouldEqual` textHTML
          content `shouldEqual` "<h1>Home Page</h1>"
    it "should deliver the content in the server's default format when the client will accept any content" do
      result <- processRequest defaultRequest
      case result of
        Left error ->
          fail $ "Request failed unexpectedly: " <> show error
        Right (Tuple mediaType content) -> do
          mediaType `shouldEqual` applicationJSON
          content `shouldEqual` (stringify $ encodeJson Default)
