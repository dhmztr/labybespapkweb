module Types exposing (..)

import Dict exposing (Dict)
import Html.Attributes exposing (id)
import Http
import Time


-- MODEL


type alias Model =
    { email : String
    , haslo : String
    , powtorz : String
    , tryb : Tryb
    , stan : Stan
    , flota : List Kierowca
    , pytanie : String
    , oceny : Dict String (List String)
    }


type Tryb
    = Logowanie
    | Rejestracja


type Stan
    = Formularz (Maybe String)
    | Wysylanie
    | Sprawdzanie
    | Wylogowany
    | Zalogowany Sesja


{-| wszystko, co aplikacja pamięta po zalogowaniu
-}
type alias Sesja =
    { email : String
    , token : String
    , strona : Strona
    , wybrane : Maybe String
    , zam : FormZamowienia
    , kom : FormKomentarzy
    , przejazd : Maybe String
    , doOceny : List String
    , zakonczony : Maybe String
    , wersja : Int
    , historia : Historia
    }


{-| odpowiedź /ja: e-mail i id auta, jeśli użytkownik ma teraz aktywny przejazd
-}
type alias Ja =
    { email : String
    , przejazd : Maybe String
    }


type Strona
    = StronaAuta
    | StronaZamowienie
    | StronaPrzejazdy
    | StronaKomentarze


{-| cel to punkt, do którego auto jedzie teraz; celKoncowy jest ustawiony tylko wtedy,
gdy auto jedzie jeszcze po klienta (cel = odbiór, celKoncowy = miejsce docelowe)
-}
type alias Kierowca =
    { id : String
    , lat : Float
    , lon : Float
    , cel : Maybe ( Float, Float )
    , celKoncowy : Maybe ( Float, Float )
    , wolne : Int
    }


type EtapKursu
    = Wolne
    | PoKlienta ( Float, Float ) ( Float, Float )
    | DoCelu ( Float, Float )


etapAuta : Kierowca -> EtapKursu
etapAuta k =
    case ( k.cel, k.celKoncowy ) of
        ( Just odbior, Just meta ) ->
            PoKlienta odbior meta

        ( Just meta, Nothing ) ->
            DoCelu meta

        ( Nothing, _ ) ->
            Wolne



type Punkt
    = Start
    | Cel


type Pole
    = StartLat
    | StartLon
    | CelLat
    | CelLon


type alias FormZamowienia =
    { startLat : String
    , startLon : String
    , celLat : String
    , celLon : String
    , miejsca : String
    , ustawiam : Punkt
    , stan : StanZam
    }


type StanZam
    = ZamPisanie (Maybe String)
    | ZamWysylanie


type alias Komentarz =
    { autor : String
    , data : String
    , ocena : Float
    , tresc : String
    }


type Lista
    = ListaPusta
    | ListaLaduje
    | ListaGotowa (List Komentarz)
    | ListaBlad


{-| jeden wiersz z /mojeprzejazdy; auto to vehicle_id zamienione na tekst, tak jak id aut w reszcie aplikacji
-}
type alias Przejazd =
    { auto : String
    , startLat : Float
    , startLon : Float
    , celLat : Float
    , celLon : Float
    , status : String
    , data : String
    }


type Historia
    = HistoriaPusta
    | HistoriaLaduje
    | HistoriaGotowa (List Przejazd)
    | HistoriaBlad


type alias FormKomentarzy =
    { wybrany : Maybe String
    , lista : Lista
    , ocena : String
    , tresc : String
    , wysylanie : Bool
    , blad : Maybe String
    , info : Maybe String
    }



type Msg
    = WpisanoEmail String
    | WpisanoHaslo String
    | WpisanoPowtorz String
    | UstawTryb Tryb
    | Zaloguj
    | Zarejestruj
    | OdpowiedzLogin (Result Http.Error String)
    | OdpowiedzRejestracja (Result Http.Error String)
    | OdpowiedzJa String (Result Http.Error Ja)
    | OdpowiedzPrzywrocenie String (Result Http.Error Ja)
    | OdpowiedzStanu Int (Result Http.Error Ja)
    | ZamknijKomunikat
    | Wyloguj
    | OdpowiedzWyloguj (Result Http.Error ())
    | NicNieRob
      -- strona główna
    | WpisanoPytanie String
      -- aplikacja po zalogowaniu
    | Tik Time.Posix
    | OdpowiedzKierowcy (Result Http.Error (List Kierowca))
    | IdzDo Strona
    | WybranoAuto String
    | OtworzOpinie String
      -- zamówienie
    | WpisanoWsp Pole String
    | UstawPunkt Punkt
    | KlikMapa Float Float
    | WpisanoMiejsca String
    | Zamow
    | OdpowiedzZamowienie (Result Http.Error Kierowca)
    | NoweZamowienie
      -- przejazdy
    | OdpowiedzPrzejazdy (Result Http.Error (List Przejazd))
      -- opinie
    | WybranoKierowce String
    | OdpowiedzKomentarze String (Result Http.Error (List Komentarz))
    | WpisanoOcene String
    | WpisanoTresc String
    | WystawKomentarz
    | OdpowiedzWystawienia (Result Http.Error ())



{-| punkty start i cel z formularza zamówienia
-}
type alias Znacznik =
    { klasa : String
    , lat : Float
    , lon : Float
    , napis : String
    }
