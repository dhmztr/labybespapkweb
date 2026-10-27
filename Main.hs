{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

import Types
import Apis
import Control.Concurrent (modifyMVar_)
import Control.Concurrent.MVar
import Control.Exception (try)
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


type FullAPI = API :<|> SwaggerSchemaUI "swagger-ui" "swagger.json" :<|> Raw

dokument :: Swagger
dokument = toSwagger (Proxy :: Proxy API)

type API =
  "zdrowie" :> Get '[JSON] String
    :<|> "login" :> ReqBody '[JSON] Poswiadczenia :> Post '[JSON] Odpowiedz
    :<|> "ja" :> Header "Authorization" String :> Get '[JSON] String
    :<|> "zamowienie" :> Header "Authorization" String :> ReqBody '[JSON] Zamowienie :> Post '[JSON] ZamowienieOdpowiedz
    :<|> "rejestracja" :> ReqBody '[JSON] Poswiadczenia :> Post '[JSON] Odpowiedz
    :<|> "wyloguj" :> Header "Authorization" String :> Post '[JSON] String
serwer :: MVar (M.Map String String) -> Connection -> Server FullAPI
serwer x y = (zdrowie :<|> login x y :<|> ja x :<|> zamowienie x :<|> rejestracja x y :<|> wyloguj x) :<|> swaggerSchemaUIServer dokument :<|> serveDirectoryFileServer "frontend/public"

main :: IO ()
main = do
  sesje <- newMVar M.empty
  conn <- liftIO (connectPostgreSQL "")
  run 8080 (serve (Proxy :: Proxy FullAPI) (serwer sesje conn))

