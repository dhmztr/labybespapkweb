{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

import Types
import Apis
import Control.Concurrent (threadDelay,modifyMVar_,forkIO, modifyMVar )
import Control.Concurrent.MVar
import Control.Exception (try)
import Data.Pool (Pool, newPool, defaultPoolConfig,withResource )
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
import Types (WylogujReq)
import System.Random (randomRIO)
import Cars (petlaKierowcy)
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime)
import Data.Bool (Bool)
import Data.Time (getCurrentTime)
import Network.Wai (Middleware,remoteHost ,pathInfo ,responseLBS )
import Network.HTTP.Types (status429)

import Database.Redis qualified as R

type FullAPI = API :<|> SwaggerSchemaUI "swagger-ui" "swagger.json" :<|> Raw

dokument :: Swagger
dokument = toSwagger (Proxy :: Proxy API)

type API =
  "zdrowie" :> Get '[JSON] String
    :<|> "login" :> ReqBody '[JSON] Poswiadczenia :> Post '[JSON] Odpowiedz
    :<|> "ja" :> Header "Authorization" String :> Get '[JSON] JaOdpowiedz
    :<|> "zamowienie" :> Header "Authorization" String :> ReqBody '[JSON] Zamowienie :> Post '[JSON] Kierowca
    :<|> "rejestracja" :> ReqBody '[JSON] Poswiadczenia :> Post '[JSON] Odpowiedz
    :<|> "wyloguj" :> Header "Authorization" String :> Post '[JSON] String
    :<|> "kierowcy" :> Get '[JSON] [Kierowca]
    :<|> "komentarze" :>  Header "Authorization" String :> ReqBody '[JSON] KomentarzReq :> Post '[JSON] [Komentarz]
    :<|> "wystawkomentarz" :> Header "Authorization"  String :> ReqBody '[JSON] Komentarz :> Post '[JSON] String
    :<|> "mojeprzejazdy" :> Header "Authorization" String :> Get '[JSON] [Przejazd]
serwer :: MVar (M.Map String String) -> MVar (M.Map String String) -> MVar (M.Map String Kierowca) ->  Pool Connection -> Server FullAPI
serwer mvtokeny mvprzejazdy mvkierowcy pool = (zdrowie :<|> login mvtokeny pool:<|> ja mvtokeny mvprzejazdy mvkierowcy  :<|> zamowienie mvtokeny mvprzejazdy mvkierowcy pool:<|> rejestracja mvtokeny pool:<|> wyloguj mvtokeny :<|> kierowcy mvkierowcy :<|> komentarzedlakierowcy mvtokeny pool:<|> dodajKomentarz mvtokeny pool:<|> mojeZamowienia mvtokeny pool) :<|> swaggerSchemaUIServer dokument :<|> serveDirectoryFileServer "frontend/public"

main :: IO ()
main = do
  sesje <- newMVar M.empty
  pool <- newPool (defaultPoolConfig (liftIO (connectPostgreSQL "")) close 60 10)
  przejazdy <- newMVar M.empty
  kierowcy_wiersze <- liftIO ( withResource  pool $ \conn -> query_ conn "SELECT id FROM vehicles" :: IO [Only Int])
  kierowcy <- wygeneruj_kierowcow kierowcy_wiersze 
  let map_kierowcow = M.fromList [(idKierowcy k,k) | k <- kierowcy ]
  mvkierowcy <- newMVar map_kierowcow 
  redisConn <- R.connect  R.defaultConnectInfo {R.connectHost = "redis", R.connectPort = R.PortNumber 6379}
  mvlimiter <- newMVar M.empty 
  mapM_ (\k -> forkIO (petlaKierowcy mvkierowcy (idKierowcy k))) map_kierowcow 
  run 8080 (limiterIP mvlimiter (serve (Proxy :: Proxy FullAPI) (serwer sesje przejazdy mvkierowcy pool)))


wygeneruj_kierowcow :: [Only Int] -> IO [Kierowca]
wygeneruj_kierowcow [] = return []
wygeneruj_kierowcow (ident:reszta) = do
                        lat_start<- randomRIO (51.05,51.15)
                        lon_start <- randomRIO (16.90,17.10)
                        miejsca <- randomRIO (2,5)
                        let kierowca = Kierowca {idKierowcy = show (fromOnly (ident)), lat = lat_start,lon = lon_start,cel = Nothing,celKoncowy=Nothing,wolne_miejsca = miejsca }
                        reszta_kierowcow <- liftIO( wygeneruj_kierowcow reszta )
                        return (kierowca:reszta_kierowcow )



sprawdzCooldown :: MVar (M.Map String (UTCTime,Int)) -> String -> Int -> NominalDiffTime -> IO Bool
sprawdzCooldown mv klucz prog czasokna = do
    teraz <- getCurrentTime 
    mapa <- readMVar mv
    case M.lookup klucz mapa of
        Nothing -> do
                  modifyMVar_ mv (\mapa -> pure (M.insert klucz (teraz ,1) mapa ))
                  return True
        (Just (czas,ilosc)) -> do 
                  if (diffUTCTime teraz czas) > czasokna
                    then do
                      modifyMVar_ mv (\mapa -> pure (M.insert klucz (teraz ,1) mapa ))
                      return True
                  else 
                    if ilosc > prog
                      then return False
                    else do
                      modifyMVar_ mv (\mapa -> pure (M.insert klucz (teraz ,ilosc + 1) mapa ))
                      return True
                        

limiterIP :: MVar (M.Map String (UTCTime,Int)) -> Middleware
limiterIP mv app req respond =
 if pathInfo req `elem` [["login"], ["rejestracja"], ["wystawkomentarz"], ["zamowienie"]]
  then do 
        let ip = takeWhile (/= ':') (show (remoteHost req))
        dozwolone <- sprawdzCooldown mv ip 5 10
        if dozwolone
          then app req respond
          else respond (responseLBS status429 [] "Za duzo zapytan")
      else app req respond
                        
                      
          
