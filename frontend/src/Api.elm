module Api exposing (..)

import Html exposing (a)
import Html.Attributes exposing (id)
import Http
import Json.Decode as D
import Json.Encode as E
import Types exposing (..)


-- HTTP


zaloguj : String -> String -> Cmd Msg
zaloguj =
    wyslijPoswiadczenia "/login" OdpowiedzLogin


zarejestruj : String -> String -> Cmd Msg
zarejestruj =
    wyslijPoswiadczenia "/rejestracja" OdpowiedzRejestracja


{-| /login i /rejestracja przyjmują ten sam JSON i odpowiadają tym samym tokenem
-}
wyslijPoswiadczenia : String -> (Result Http.Error String -> Msg) -> String -> String -> Cmd Msg
wyslijPoswiadczenia url naOdpowiedz email haslo =
    Http.post
        { url = url
        , body =
            Http.jsonBody
                (E.object
                    [ ( "email", E.string email )
                    , ( "haslo", E.string haslo )
                    ]
                )
        , expect = Http.expectJson naOdpowiedz (D.field "token" D.string)
        }


pobierzJa : String -> Cmd Msg
pobierzJa token =
    Http.request
        { method = "GET"
        , headers = [ naglowekBearer token ]
        , url = "/ja"
        , body = Http.emptyBody
        , expect = Http.expectJson (OdpowiedzJa token) jaDekoder
        , timeout = Nothing
        , tracker = Nothing
        }


przywroc : String -> Cmd Msg
przywroc token =
    Http.request
        { method = "GET"
        , headers = [ naglowekBearer token ]
        , url = "/ja"
        , body = Http.emptyBody
        , expect = Http.expectJson (OdpowiedzPrzywrocenie token) jaDekoder
        , timeout = Nothing
        , tracker = Nothing
        }


{-| co 2 sekundy: czy przejazd nadal trwa; wersja pozwala odrzucić spóźnione odpowiedzi
-}
pobierzStan : String -> Int -> Cmd Msg
pobierzStan token wersja =
    Http.request
        { method = "GET"
        , headers = [ naglowekBearer token ]
        , url = "/ja"
        , body = Http.emptyBody
        , expect = Http.expectJson (OdpowiedzStanu wersja) jaDekoder
        , timeout = Nothing
        , tracker = Nothing
        }


jaDekoder : D.Decoder Ja
jaDekoder =
    D.map2 Ja
        (D.field "mojemail" D.string)
        (D.field "przejadz" (D.nullable D.string))


wylogujNaSerwerze : String -> Cmd Msg
wylogujNaSerwerze token =
    Http.request
        { method = "POST"
        , headers = [ naglowekBearer token ]
        , url = "/wyloguj"
        , body = Http.emptyBody
        , expect = Http.expectWhatever OdpowiedzWyloguj
        , timeout = Nothing
        , tracker = Nothing
        }


{-| lista aut jest publiczna, bez tokenu
-}
pobierzKierowcow : Cmd Msg
pobierzKierowcow =
    Http.get
        { url = "/kierowcy"
        , expect = Http.expectJson OdpowiedzKierowcy (D.list kierowcaDekoder)
        }


zamow : String -> Float -> Float -> Float -> Float -> Int -> Cmd Msg
zamow token startLat startLon celLat celLon ileMiejsc =
    Http.request
        { method = "POST"
        , headers = [ naglowekBearer token ]
        , url = "/zamowienie"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "lat_startowy", E.float startLat )
                    , ( "lon_startowy", E.float startLon )
                    , ( "lat_koncowy", E.float celLat )
                    , ( "lon_koncowy", E.float celLon )
                    , ( "miejsca", E.int ileMiejsc )
                    ]
                )
        , expect = Http.expectJson OdpowiedzZamowienie kierowcaDekoder
        , timeout = Nothing
        , tracker = Nothing
        }


pobierzPrzejazdy : String -> Cmd Msg
pobierzPrzejazdy token =
    Http.request
        { method = "GET"
        , headers = [ naglowekBearer token ]
        , url = "/mojeprzejazdy"
        , body = Http.emptyBody
        , expect = Http.expectJson OdpowiedzPrzejazdy (D.list przejazdDekoder)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| mimo że to odczyt, backend chce POST z ciałem {"reqidkier": ...}
-}
pobierzKomentarze : String -> String -> Cmd Msg
pobierzKomentarze token id =
    Http.request
        { method = "POST"
        , headers = [ naglowekBearer token ]
        , url = "/komentarze"
        , body = Http.jsonBody (E.object [ ( "reqidkier", E.string id ) ])
        , expect = Http.expectJson (OdpowiedzKomentarze id) (D.list komentarzDekoder)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| backend wymaga w JSON-ie pól wystawiajacy i czasotrzymania, ale ignoruje je:
autora bierze z tokenu, a datę ustawia sam
-}
wystawKomentarz : String -> String -> Float -> String -> Cmd Msg
wystawKomentarz token id ocena tresc =
    Http.request
        { method = "POST"
        , headers = [ naglowekBearer token ]
        , url = "/wystawkomentarz"
        , body =
            Http.jsonBody
                (E.object
                    [ ( "idKier", E.string id )
                    , ( "wystawiajacy", E.string "" )
                    , ( "czasotrzymania", E.string "" )
                    , ( "ocena", E.float ocena )
                    , ( "tresc", E.string tresc )
                    ]
                )
        , expect = Http.expectWhatever OdpowiedzWystawienia
        , timeout = Nothing
        , tracker = Nothing
        }


kierowcaDekoder : D.Decoder Kierowca
kierowcaDekoder =
    let
        para =
            D.nullable (D.map2 Tuple.pair (D.index 0 D.float) (D.index 1 D.float))
    in
    D.map6 Kierowca
        (D.field "idKierowcy" D.string)
        (D.field "lat" D.float)
        (D.field "lon" D.float)
        (D.field "cel" para)
        (D.field "celKoncowy" para)
        (D.field "wolne_miejsca" D.int)


przejazdDekoder : D.Decoder Przejazd
przejazdDekoder =
    D.map7 Przejazd
        (D.field "vehicle_id" (D.map String.fromInt D.int))
        (D.field "pickup_lat" D.float)
        (D.field "pickup_lng" D.float)
        (D.field "dropoff_lat" D.float)
        (D.field "dropoff_lng" D.float)
        (D.field "status" D.string)
        (D.field "created_at" D.string)


komentarzDekoder : D.Decoder Komentarz
komentarzDekoder =
    D.map4 Komentarz
        (D.field "wystawiajacy" D.string)
        (D.field "czasotrzymania" D.string)
        (D.field "ocena" D.float)
        (D.field "tresc" D.string)


{-| backend (wszystko poza /login i /rejestracja) wymaga prefiksu "Bearer "
-}
naglowekBearer : String -> Http.Header
naglowekBearer token =
    Http.header "Authorization" ("Bearer " ++ token)
