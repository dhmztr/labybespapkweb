module Types where

import Data.Aeson
import Data.Swagger (Swagger, ToSchema)
import Distribution.Compat.Prelude (Float)
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
    { lat_startowy :: Double
    , lon_startowy :: Double
    , lat_koncowy :: Double
    , lon_koncowy :: Double
    , miejsca :: Int
    }
    deriving (Show, Generic)
data ZamowienieOdpowiedz = ZamowienieOdpowiedz
    { driver_id :: String
    }
    deriving (Show, Generic)
data Kierowca = Kierowca
    { idKierowcy :: String
    , lat :: Double
    , lon :: Double
    , cel :: Maybe (Double, Double)
    , wolne_miejsca :: Int
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
instance ToJSON Kierowca
instance ToSchema Kierowca
