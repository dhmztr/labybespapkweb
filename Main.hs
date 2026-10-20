{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

import Control.Concurrent.MVar
import Control.Monad.IO.Class (MonadIO (liftIO))
import Crypto.Random (MonadRandom (getRandomBytes))
import Data.Aeson
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Map qualified as M
import Data.Password.Argon2
import Data.Swagger (Swagger, ToSchema)
import Data.Text qualified as T
import Database.PostgreSQL.Simple
import GHC.Generics (Generic)
import Network.Wai.Handler.Warp (run)
import Numeric (showIntAtBase)
import Servant
import Servant.Swagger (toSwagger)
import Servant.Swagger.UI (SwaggerSchemaUI, swaggerSchemaUIServer)

generujToken :: IO String
generujToken = do
  bytesarr <- getRandomBytes 32 :: IO BS.ByteString
  let intarr = map fromIntegral (BS.unpack bytesarr)
  let hex = concatMap byteToHex intarr
  pure hex

type FullAPI = API :<|> SwaggerSchemaUI "swagger-ui" "swagger.json"

dokument :: Swagger
dokument = toSwagger (Proxy :: Proxy API)

passwordHash :: PasswordHash Argon2
passwordHash = PasswordHash "$argon2id$v=19$m=65536,t=2,p=1$PycdySns1NErahSML9ctNA$9HDgpC/b2j+us2dCmsrSnK4CRv3bHTYinpGDh10KM/0"
data Logowanie = Logowanie
  { email :: String
  , haslo :: String
  }
  deriving (Show, Generic)
data Odpowiedz = Odpowiedz
  { token :: String
  }
  deriving (Show, Generic)
instance FromJSON Logowanie
instance ToJSON Odpowiedz
instance ToSchema Logowanie
instance ToSchema Odpowiedz
type API =
  "zdrowie" :> Get '[JSON] String
    :<|> "login" :> ReqBody '[JSON] Logowanie :> Post '[JSON] Odpowiedz
    :<|> "ja" :> Header "Authorization" String :> Get '[JSON] String

login :: MVar (M.Map String String) -> Connection -> Logowanie -> (Handler Odpowiedz)
login mv conn user = do
  rows <- (liftIO (query conn "SELECT password_hash FROM users WHERE email = ?" (Only (email user)) :: IO [Only T.Text]))
  let (hash, istnieje) = case rows of
        (Only h : _) -> ((PasswordHash h), True)
        [] -> (passwordHash, False)
  if ((checkPassword (mkPassword (T.pack (haslo user))) hash) == PasswordCheckSuccess) && istnieje
    then do
      token <- liftIO generujToken
      liftIO (modifyMVar_ mv (\mapa -> pure (M.insert token (email user) mapa)))
      return (Odpowiedz token)
    else
      throwError err401

zdrowie :: MVar (M.Map String String) -> (Handler String)
zdrowie x = do
  zaw <- liftIO (readMVar x)
  return (show (M.size zaw))
ja :: MVar (M.Map String String) -> Maybe String -> Handler String
ja mv head = case head of
  Just x -> do
    mapa <- liftIO (readMVar mv)
    maybe (throwError err401) return (M.lookup x mapa)
  Nothing -> throwError err401
serwer :: MVar (M.Map String String) -> Connection -> Server FullAPI
serwer x y = (zdrowie x :<|> login x y :<|> ja x) :<|> swaggerSchemaUIServer dokument

main :: IO ()
main = do
  sesje <- newMVar M.empty
  conn <- liftIO (connectPostgreSQL "")
  run 8080 (serve (Proxy :: Proxy FullAPI) (serwer sesje conn))

byteToHex :: Int -> String
byteToHex number
  | length wynik == 1 = "0" ++ wynik
  | otherwise = wynik
 where
  wynik = showIntAtBase 16 intToDigit number ""
