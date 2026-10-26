module Types where

import Data.Aeson
import Data.Swagger (Swagger, ToSchema)
import GHC.Generics (Generic)

data Poswiadczenia = Poswiadczenia
    { email :: String
    , haslo :: String
    }
    deriving (Show, Generic)
data WylogujReq = WylogujReq
    { userToken :: String
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

instance FromJSON Poswiadczenia
instance ToJSON Odpowiedz
instance ToSchema Poswiadczenia
instance ToSchema Odpowiedz
instance FromJSON Zamowienie
instance ToJSON ZamowienieOdpowiedz
instance FromJSON WylogujReq
instance ToSchema WylogujReq
instance ToSchema Zamowienie
instance ToSchema ZamowienieOdpowiedz
