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
    , celKoncowy :: Maybe (Double, Double)
    , wolne_miejsca :: Int
    }
    deriving (Show, Generic)
data Komentarz = Komentarz
    { idKier :: String
    , wystawiajacy :: String
    , czasotrzymania :: String
    , ocena :: Double
    , tresc :: String
    }
    deriving (Show, Generic)
data KomentarzReq = KomentarzReq
    { reqidkier :: String
    }
    deriving (Show, Generic)
data JaOdpowiedz = JaOdpowiedz
    { mojemail :: String
    , przejadz :: Maybe String
    }
    deriving (Show, Generic)
data WyswietlZamowieniaReq = WyswietlZamowieniaReq
    { emailklienta :: String
    }
    deriving (Show, Generic)
data Przejazd = Przejazd
    { vehicle_id :: Int
    , pickup_lat :: Double
    , pickup_lng :: Double
    , dropoff_lat :: Double
    , dropoff_lng :: Double
    , status :: String
    , created_at :: String
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
instance ToJSON Komentarz
instance FromJSON Komentarz
instance ToSchema Komentarz
instance FromJSON KomentarzReq
instance ToSchema KomentarzReq
instance ToJSON JaOdpowiedz
instance ToSchema JaOdpowiedz
instance ToJSON Przejazd
instance ToSchema Przejazd
