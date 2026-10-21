{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

import Control.Concurrent.MVar
import Control.Monad.IO.Class (MonadIO (liftIO))
import Crypto.Random (MonadRandom (getRandomBytes))
import Data.Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy.Char8 qualified as BL8
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

type FullAPI = API :<|> SwaggerSchemaUI "swagger-ui" "swagger.json" :<|> Raw

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
data Zamowienie = Zamowienie
  { adres_startowy :: String
  , adres_docelowy :: String
  , miejsca :: Int
  }
  deriving (Show, Generic)
data ZamowienieOdpowiedz = ZamowienieOdpowiedz
  { driver_id :: String
  }
  deriving (Show, Generic)
instance FromJSON Logowanie
instance ToJSON Odpowiedz
instance ToSchema Logowanie
instance ToSchema Odpowiedz
instance FromJSON Zamowienie
instance ToJSON ZamowienieOdpowiedz
instance ToSchema Zamowienie
instance ToSchema ZamowienieOdpowiedz
zweryfikujZamowienie :: String -> String -> Int -> Either String Zamowienie
zweryfikujZamowienie x y z
  | null x = Left "Niepoprawny adres startowy"
  | null y = Left "Niepoprawna destynacja"
  | (z > 4) || (z < 1) = Left "Ilosc pasazerow poza zasiegiem"
  | otherwise = Right (Zamowienie x y z)
type API =
  "zdrowie" :> Get '[JSON] String
    :<|> "login" :> ReqBody '[JSON] Logowanie :> Post '[JSON] Odpowiedz
    :<|> "ja" :> Header "Authorization" String :> Get '[JSON] String
    :<|> "zamowienie" :> Header "Authorization" String :> ReqBody '[JSON] Zamowienie :> Post '[JSON] ZamowienieOdpowiedz
zamowienie :: MVar (M.Map String String) -> Maybe String -> Zamowienie -> (Handler ZamowienieOdpowiedz)
zamowienie mv naglowek zamowieniereq = case naglowek of
  (Just x) -> do
    mapa <- liftIO (readMVar mv)
    case (M.lookup x mapa) of
      (Just _) -> do
        case zweryfikujZamowienie (adres_startowy zamowieniereq) (adres_docelowy zamowieniereq) (miejsca zamowieniereq) of
          Right _zamowienieOk -> do
            let odpowiedz = ZamowienieOdpowiedz "kierowca1"
            return odpowiedz
          Left powod -> throwError (err400{errBody = (BL8.pack ("Nie mozna ukonczyc zamowienia: " ++ powod))})
      Nothing -> throwError (err401{errBody = BL8.pack ("Wygasly token ")})
  Nothing -> throwError (err401{errBody = (BL8.pack "Brak tokenu autoryzujacego")})

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

zdrowie :: (Handler String)
zdrowie = return "ok"
ja :: MVar (M.Map String String) -> Maybe String -> Handler String
ja mv head = case head of
  Just x -> do
    mapa <- liftIO (readMVar mv)
    maybe (throwError err401) return (M.lookup x mapa)
  Nothing -> throwError err401
serwer :: MVar (M.Map String String) -> Connection -> Server FullAPI
serwer x y = (zdrowie :<|> login x y :<|> ja x :<|> zamowienie x) :<|> swaggerSchemaUIServer dokument :<|> serveDirectoryFileServer "frontend/public"

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
