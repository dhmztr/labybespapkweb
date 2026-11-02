port module Main exposing (main)

import Browser
import Html exposing (Html, button, div, form, h1, input, label, option, p, select, span, table, tbody, td, text, textarea, th, thead, tr)
import Html.Attributes exposing (attribute, autocomplete, class, classList, disabled, for, id, maxlength, required, rows, selected, style, title, type_, value)
import Html.Events exposing (on, onClick, onInput, onSubmit)
import Http
import Json.Decode as D
import Json.Encode as E
import Time


port zapiszToken : String -> Cmd msg


port usunToken : () -> Cmd msg


{-| flagą jest token zapamiętany w localStorage (albo null)
-}
main : Program (Maybe String) Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


{-| lista aut odświeża się sama co 2 sekundy, ale tylko dla zalogowanego
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    case model.stan of
        Zalogowany _ ->
            Time.every 2000 Tik

        _ ->
            Sub.none



-- MODEL


type alias Model =
    { email : String
    , haslo : String
    , powtorz : String
    , tryb : Tryb
    , stan : Stan
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
    , kierowcy : List Kierowca
    , zam : FormZamowienia
    , kom : FormKomentarzy
    }


type Strona
    = StronaAuta
    | StronaZamowienie
    | StronaKomentarze


type alias Kierowca =
    { id : String
    , lat : Float
    , lon : Float
    , cel : Maybe ( Float, Float )
    , wolne : Int
    }


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
    | ZamGotowe Kierowca


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


type alias FormKomentarzy =
    { wybrany : Maybe String
    , lista : Lista
    , ocena : String
    , tresc : String
    , wysylanie : Bool
    , blad : Maybe String
    , info : Maybe String
    }


pustaZamowienie : FormZamowienia
pustaZamowienie =
    { startLat = ""
    , startLon = ""
    , celLat = ""
    , celLon = ""
    , miejsca = "1"
    , ustawiam = Start
    , stan = ZamPisanie Nothing
    }


puste : FormKomentarzy
puste =
    { wybrany = Nothing
    , lista = ListaPusta
    , ocena = "5"
    , tresc = ""
    , wysylanie = False
    , blad = Nothing
    , info = Nothing
    }


nowaSesja : String -> String -> Sesja
nowaSesja email token =
    { email = email
    , token = token
    , strona = StronaAuta
    , kierowcy = []
    , zam = pustaZamowienie
    , kom = puste
    }


poczatek : Model
poczatek =
    { email = "", haslo = "", powtorz = "", tryb = Logowanie, stan = Formularz Nothing }


init : Maybe String -> ( Model, Cmd Msg )
init zapamietany =
    case zapamietany of
        Just token ->
            -- sesja z poprzedniej wizyty: sprawdzamy u backendu, czy token nadal działa
            ( { poczatek | stan = Sprawdzanie }, przywroc token )

        Nothing ->
            ( poczatek, Cmd.none )



-- UPDATE


type Msg
    = WpisanoEmail String
    | WpisanoHaslo String
    | WpisanoPowtorz String
    | PrzelaczTryb
    | Zaloguj
    | Zarejestruj
    | OdpowiedzLogin (Result Http.Error String)
    | OdpowiedzRejestracja (Result Http.Error String)
    | OdpowiedzJa String (Result Http.Error String)
    | OdpowiedzPrzywrocenie String (Result Http.Error String)
    | Wyloguj
    | OdpowiedzWyloguj (Result Http.Error ())
    | WrocDoLogowania
      -- aplikacja po zalogowaniu
    | Tik Time.Posix
    | OdpowiedzKierowcy (Result Http.Error (List Kierowca))
    | IdzDo Strona
    | OtworzOpinie String
      -- zamówienie
    | WpisanoWsp Pole String
    | UstawPunkt Punkt
    | KlikMapa Float Float
    | WpisanoMiejsca String
    | Zamow
    | OdpowiedzZamowienie (Result Http.Error Kierowca)
    | NoweZamowienie
      -- opinie
    | WybranoKierowce String
    | OdpowiedzKomentarze String (Result Http.Error (List Komentarz))
    | WpisanoOcene String
    | WpisanoTresc String
    | WystawKomentarz
    | OdpowiedzWystawienia (Result Http.Error ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        WpisanoEmail email ->
            ( { model | email = email }, Cmd.none )

        WpisanoHaslo haslo ->
            ( { model | haslo = haslo }, Cmd.none )

        WpisanoPowtorz powtorz ->
            ( { model | powtorz = powtorz }, Cmd.none )

        PrzelaczTryb ->
            ( { model | tryb = innyTryb model.tryb, haslo = "", powtorz = "", stan = Formularz Nothing }
            , Cmd.none
            )

        Zaloguj ->
            ( { model | stan = Wysylanie }, zaloguj model.email model.haslo )

        Zarejestruj ->
            if model.haslo /= model.powtorz then
                ( { model | stan = Formularz (Just "Hasła nie są takie same.") }, Cmd.none )

            else
                ( { model | stan = Wysylanie }, zarejestruj model.email model.haslo )

        OdpowiedzLogin (Ok token) ->
            ( model, pobierzJa token )

        OdpowiedzLogin (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        OdpowiedzRejestracja (Ok token) ->
            -- backend po rejestracji od razu zwraca token, więc logujemy jak po /login
            ( model, pobierzJa token )

        OdpowiedzRejestracja (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        OdpowiedzJa token (Ok email) ->
            ( { model | haslo = "", powtorz = "", stan = Zalogowany (nowaSesja email token) }
            , Cmd.batch [ zapiszToken token, pobierzKierowcow ]
            )

        OdpowiedzJa _ (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        OdpowiedzPrzywrocenie token (Ok email) ->
            ( { model | stan = Zalogowany (nowaSesja email token) }, pobierzKierowcow )

        OdpowiedzPrzywrocenie _ (Err (Http.BadStatus 401)) ->
            -- token wygasł albo został unieważniony
            ( { model | stan = Formularz Nothing }, usunToken () )

        OdpowiedzPrzywrocenie _ (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        Wyloguj ->
            case model.stan of
                Zalogowany dane ->
                    -- lokalnie wylogowujemy od razu, nie czekając na backend
                    ( { poczatek | stan = Wylogowany }
                    , Cmd.batch [ usunToken (), wylogujNaSerwerze dane.token ]
                    )

                _ ->
                    ( model, Cmd.none )

        OdpowiedzWyloguj _ ->
            ( model, Cmd.none )

        WrocDoLogowania ->
            ( poczatek, Cmd.none )

        Tik _ ->
            ( model, pobierzKierowcow )

        OdpowiedzKierowcy (Ok lista) ->
            zSesja (\s -> ( { s | kierowcy = List.sortBy numerAuta lista }, Cmd.none )) model

        OdpowiedzKierowcy (Err _) ->
            -- lista odświeża się co 2 s, więc chwilowy błąd po prostu zostawia stare dane
            ( model, Cmd.none )

        IdzDo strona ->
            zSesja (\s -> ( { s | strona = strona }, Cmd.none )) model

        OtworzOpinie id ->
            zSesja
                (\s ->
                    let
                        ( s2, cmd ) =
                            wybierzKierowce id s
                    in
                    ( { s2 | strona = StronaKomentarze }, cmd )
                )
                model

        WpisanoWsp pole wartosc ->
            zSesja (\s -> ( { s | zam = ustawPole pole wartosc s.zam }, Cmd.none )) model

        UstawPunkt punkt ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | ustawiam = punkt } }, Cmd.none )) model

        KlikMapa lat lon ->
            zSesja
                (\s ->
                    let
                        z =
                            s.zam
                    in
                    case z.ustawiam of
                        Start ->
                            -- po ustawieniu startu przełączamy się od razu na cel
                            ( { s | zam = { z | startLat = zaokr4 lat, startLon = zaokr4 lon, ustawiam = Cel } }, Cmd.none )

                        Cel ->
                            ( { s | zam = { z | celLat = zaokr4 lat, celLon = zaokr4 lon } }, Cmd.none )
                )
                model

        WpisanoMiejsca miejsca ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | miejsca = miejsca } }, Cmd.none )) model

        Zamow ->
            zSesja
                (\s ->
                    let
                        z =
                            s.zam
                    in
                    case Maybe.map5 (zamow s.token) (parsuj z.startLat) (parsuj z.startLon) (parsuj z.celLat) (parsuj z.celLon) (String.toInt z.miejsca) of
                        Just cmd ->
                            ( { s | zam = { z | stan = ZamWysylanie } }, cmd )

                        Nothing ->
                            ( { s | zam = { z | stan = ZamPisanie (Just "Podaj poprawne współrzędne albo kliknij na mapie.") } }, Cmd.none )
                )
                model

        OdpowiedzZamowienie (Ok kierowca) ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | stan = ZamGotowe kierowca } }, Cmd.none )) model

        OdpowiedzZamowienie (Err (Http.BadStatus 401)) ->
            sesjaWygasla

        OdpowiedzZamowienie (Err blad) ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | stan = ZamPisanie (Just (opisBleduZamowienia blad)) } }, Cmd.none )) model

        NoweZamowienie ->
            zSesja (\s -> ( { s | zam = pustaZamowienie }, Cmd.none )) model

        WybranoKierowce id ->
            zSesja (wybierzKierowce id) model

        OdpowiedzKomentarze _ (Err (Http.BadStatus 401)) ->
            sesjaWygasla

        OdpowiedzKomentarze id wynik ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    -- odpowiedź dla auta, które użytkownik już zmienił, ignorujemy
                    if k.wybrany /= Just id then
                        ( s, Cmd.none )

                    else
                        case wynik of
                            Ok lista ->
                                ( { s | kom = { k | lista = ListaGotowa lista } }, Cmd.none )

                            Err _ ->
                                ( { s | kom = { k | lista = ListaBlad } }, Cmd.none )
                )
                model

        WpisanoOcene ocena ->
            zSesja (\s -> let k = s.kom in ( { s | kom = { k | ocena = ocena } }, Cmd.none )) model

        WpisanoTresc tresc ->
            zSesja (\s -> let k = s.kom in ( { s | kom = { k | tresc = tresc } }, Cmd.none )) model

        WystawKomentarz ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    case k.wybrany of
                        Nothing ->
                            ( { s | kom = { k | blad = Just "Najpierw wybierz auto.", info = Nothing } }, Cmd.none )

                        Just id ->
                            if String.trim k.tresc == "" then
                                ( { s | kom = { k | blad = Just "Wpisz treść opinii.", info = Nothing } }, Cmd.none )

                            else
                                ( { s | kom = { k | wysylanie = True, blad = Nothing, info = Nothing } }
                                , wystawKomentarz s.token id (Maybe.withDefault 5 (String.toFloat k.ocena)) k.tresc
                                )
                )
                model

        OdpowiedzWystawienia (Ok ()) ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    ( { s | kom = { k | wysylanie = False, tresc = "", info = Just "Dziękujemy za opinię." } }
                    , case k.wybrany of
                        Just id ->
                            pobierzKomentarze s.token id

                        Nothing ->
                            Cmd.none
                    )
                )
                model

        OdpowiedzWystawienia (Err (Http.BadStatus 401)) ->
            sesjaWygasla

        OdpowiedzWystawienia (Err _) ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    ( { s | kom = { k | wysylanie = False, blad = Just "Nie udało się dodać opinii. Spróbuj ponownie." } }, Cmd.none )
                )
                model


{-| zmienia coś w sesji tylko wtedy, gdy ktoś jest zalogowany; w innych stanach nic nie robi
-}
zSesja : (Sesja -> ( Sesja, Cmd Msg )) -> Model -> ( Model, Cmd Msg )
zSesja zmiana model =
    case model.stan of
        Zalogowany sesja ->
            let
                ( nowa, cmd ) =
                    zmiana sesja
            in
            ( { model | stan = Zalogowany nowa }, cmd )

        _ ->
            ( model, Cmd.none )


{-| backend odpowiedział 401: token nie działa, wracamy do logowania
-}
sesjaWygasla : ( Model, Cmd Msg )
sesjaWygasla =
    ( { poczatek | stan = Formularz Nothing }, usunToken () )


wybierzKierowce : String -> Sesja -> ( Sesja, Cmd Msg )
wybierzKierowce id s =
    let
        k =
            s.kom
    in
    if id == "" then
        ( { s | kom = { k | wybrany = Nothing, lista = ListaPusta, blad = Nothing, info = Nothing } }, Cmd.none )

    else
        ( { s | kom = { k | wybrany = Just id, lista = ListaLaduje, blad = Nothing, info = Nothing } }
        , pobierzKomentarze s.token id
        )


ustawPole : Pole -> String -> FormZamowienia -> FormZamowienia
ustawPole pole wartosc z =
    case pole of
        StartLat ->
            { z | startLat = wartosc }

        StartLon ->
            { z | startLon = wartosc }

        CelLat ->
            { z | celLat = wartosc }

        CelLon ->
            { z | celLon = wartosc }


{-| akceptuje i kropkę, i przecinek: "51,1" i "51.1"
-}
parsuj : String -> Maybe Float
parsuj tekst =
    String.toFloat (String.replace "," "." (String.trim tekst))


numerAuta : Kierowca -> Int
numerAuta k =
    Maybe.withDefault 0 (String.toInt k.id)


zaokr4 : Float -> String
zaokr4 x =
    String.fromFloat (toFloat (round (x * 10000)) / 10000)


innyTryb : Tryb -> Tryb
innyTryb tryb =
    case tryb of
        Logowanie ->
            Rejestracja

        Rejestracja ->
            Logowanie


opisBledu : Http.Error -> String
opisBledu blad =
    case blad of
        Http.BadStatus 401 ->
            "Nieprawidłowy e-mail lub hasło."

        Http.BadStatus 409 ->
            "Rejestracja nie powiodła się, spróbuj ponownie."

        Http.NetworkError ->
            "Brak połączenia z serwerem."

        _ ->
            "Coś poszło nie tak. Spróbuj ponownie."


opisBleduZamowienia : Http.Error -> String
opisBleduZamowienia blad =
    case blad of
        Http.BadStatus 400 ->
            "Niepoprawne zamówienie. Sprawdź współrzędne i liczbę miejsc."

        Http.BadStatus 409 ->
            "Masz już aktywny przejazd."

        Http.NetworkError ->
            "Brak połączenia z serwerem."

        _ ->
            "Coś poszło nie tak. Spróbuj ponownie."



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
        , expect = Http.expectJson (OdpowiedzJa token) D.string
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
        , expect = Http.expectJson (OdpowiedzPrzywrocenie token) D.string
        , timeout = Nothing
        , tracker = Nothing
        }


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
zamow token startLat startLon celLat celLon miejsca =
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
                    , ( "miejsca", E.int miejsca )
                    ]
                )
        , expect = Http.expectJson OdpowiedzZamowienie kierowcaDekoder
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
    D.map5 Kierowca
        (D.field "idKierowcy" D.string)
        (D.field "lat" D.float)
        (D.field "lon" D.float)
        (D.field "cel" (D.nullable (D.map2 Tuple.pair (D.index 0 D.float) (D.index 1 D.float))))
        (D.field "wolne_miejsca" D.int)


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



-- VIEW


view : Model -> Html Msg
view model =
    div
        [ classList
            [ ( "karta", True )
            , ( "szeroka"
              , case model.stan of
                    Zalogowany _ ->
                        True

                    _ ->
                        False
              )
            ]
        ]
        (case model.stan of
            Zalogowany sesja ->
                widokAplikacji sesja

            Sprawdzanie ->
                [ p [] [ text "Sprawdzanie sesji…" ] ]

            Wylogowany ->
                [ h1 [] [ text "Wylogowano" ]
                , p [] [ text "Zostałeś pomyślnie wylogowany." ]
                , button [ onClick WrocDoLogowania ] [ text "Zaloguj się ponownie" ]
                ]

            Formularz blad ->
                formularz model False blad

            Wysylanie ->
                formularz model True Nothing
        )


widokAplikacji : Sesja -> List (Html Msg)
widokAplikacji s =
    [ div [ class "gora" ]
        [ div [ class "zakladki" ]
            [ zakladka s StronaAuta "Auta"
            , zakladka s StronaZamowienie "Zamówienie"
            , zakladka s StronaKomentarze "Opinie"
            ]
        , div [ class "uzytkownik" ]
            [ span [ class "szary" ] [ text s.email ]
            , button [ type_ "button", class "link", onClick Wyloguj ] [ text "Wyloguj" ]
            ]
        ]
    , case s.strona of
        StronaAuta ->
            div [] (widokAut s)

        StronaZamowienie ->
            div [] (widokZamowienia s)

        StronaKomentarze ->
            div [] (widokOpinii s)
    ]


zakladka : Sesja -> Strona -> String -> Html Msg
zakladka s strona napis =
    button
        [ type_ "button"
        , classList [ ( "zakladka", True ), ( "aktywna", s.strona == strona ) ]
        , onClick (IdzDo strona)
        ]
        [ text napis ]



-- strona główna: auta


widokAut : Sesja -> List (Html Msg)
widokAut s =
    [ h1 [] [ text "Auta" ]
    , mapa False s.kierowcy []
    , p [ class "legenda" ]
        [ span [ class "kropka wolne" ] [], text " wolne   "
        , span [ class "kropka zajete" ] [], text " w trasie"
        ]
    , if List.isEmpty s.kierowcy then
        p [ class "szary" ] [ text "Brak aut do wyświetlenia." ]

      else
        table [ class "tabela" ]
            [ thead []
                [ tr []
                    [ th [] [ text "Auto" ]
                    , th [] [ text "Status" ]
                    , th [] [ text "Miejsca" ]
                    , th [] [ text "Pozycja" ]
                    , th [] []
                    ]
                ]
            , tbody [] (List.map wierszAuta s.kierowcy)
            ]
    ]


wierszAuta : Kierowca -> Html Msg
wierszAuta k =
    tr []
        [ td [] [ text ("#" ++ k.id) ]
        , td [] [ text (if k.cel == Nothing then "wolne" else "w trasie") ]
        , td [] [ text (String.fromInt k.wolne) ]
        , td [ class "szary" ] [ text (zaokr4 k.lat ++ ", " ++ zaokr4 k.lon) ]
        , td [] [ button [ type_ "button", class "maly", onClick (OtworzOpinie k.id) ] [ text "Opinie" ] ]
        ]



-- mapa: prosty plan okolic Wrocławia, bez bibliotek zewnętrznych


{-| zakres współrzędnych widoczny na mapie
-}
type alias Granice =
    { latMin : Float
    , latMax : Float
    , lonMin : Float
    , lonMax : Float
    }


{-| domyślnie okolice Wrocławia, ale auta błądzą losowo i z czasem odpływają,
więc zakres rozszerzamy tak, żeby zawsze mieściły się wszystkie auta i punkty
(zaokrąglony do 0,05°, żeby mapa nie "pływała" przy każdym ruchu auta)
-}
granice : List Kierowca -> List Znacznik -> Granice
granice kierowcy punkty =
    let
        szerokosci =
            51.0 :: 51.2 :: (List.map .lat kierowcy ++ List.map .lat punkty)

        dlugosci =
            16.85 :: 17.15 :: (List.map .lon kierowcy ++ List.map .lon punkty)

        dol x =
            toFloat (floor (x / 0.05)) * 0.05

        gora x =
            toFloat (ceiling (x / 0.05)) * 0.05
    in
    { latMin = dol (Maybe.withDefault 51.0 (List.minimum szerokosci))
    , latMax = gora (Maybe.withDefault 51.2 (List.maximum szerokosci))
    , lonMin = dol (Maybe.withDefault 16.85 (List.minimum dlugosci))
    , lonMax = gora (Maybe.withDefault 17.15 (List.maximum dlugosci))
    }


{-| punkty start i cel z formularza zamówienia
-}
type alias Znacznik =
    { klasa : String
    , lat : Float
    , lon : Float
    , napis : String
    }


mapa : Bool -> List Kierowca -> List Znacznik -> Html Msg
mapa klikalna kierowcy punkty =
    let
        g =
            granice kierowcy punkty
    in
    div
        (class
            (if klikalna then
                "mapa klikalna"

             else
                "mapa"
            )
            :: (if klikalna then
                    [ on "click" (klikDekoder g) ]

                else
                    []
               )
        )
        (List.map (znacznikAuta g) kierowcy ++ List.map (znacznikPunktu g) punkty)


{-| pozycja kliknięcia w pikselach zamieniamy na współrzędne geograficzne;
znaczniki mają pointer-events: none, więc target to zawsze sama mapa
-}
klikDekoder : Granice -> D.Decoder Msg
klikDekoder g =
    D.map4
        (\x y szer wys ->
            KlikMapa
                (g.latMax - y / wys * (g.latMax - g.latMin))
                (g.lonMin + x / szer * (g.lonMax - g.lonMin))
        )
        (D.field "offsetX" D.float)
        (D.field "offsetY" D.float)
        (D.at [ "target", "offsetWidth" ] D.float)
        (D.at [ "target", "offsetHeight" ] D.float)


pozycja : Granice -> Float -> Float -> List (Html.Attribute Msg)
pozycja g lat lon =
    [ style "left" (procent ((lon - g.lonMin) / (g.lonMax - g.lonMin)))
    , style "top" (procent ((g.latMax - lat) / (g.latMax - g.latMin)))
    ]


procent : Float -> String
procent u =
    String.fromFloat (clamp 0 100 (u * 100)) ++ "%"


znacznikAuta : Granice -> Kierowca -> Html Msg
znacznikAuta g k =
    div
        (classList [ ( "auto", True ), ( "zajete", k.cel /= Nothing ) ]
            :: title ("Auto #" ++ k.id)
            :: pozycja g k.lat k.lon
        )
        [ text k.id ]


znacznikPunktu : Granice -> Znacznik -> Html Msg
znacznikPunktu g z =
    div (class ("punkt " ++ z.klasa) :: pozycja g z.lat z.lon) [ text z.napis ]



-- zamówienie


widokZamowienia : Sesja -> List (Html Msg)
widokZamowienia s =
    let
        z =
            s.zam
    in
    case z.stan of
        ZamGotowe k ->
            [ h1 [] [ text "Zamówienie przyjęte" ]
            , p [] [ text ("Przydzielono auto nr " ++ k.id ++ ".") ]
            , mapa False s.kierowcy (punktyZamowienia z)
            , p [ class "legenda" ]
                [ span [ class "znak start" ] [ text "S" ], text " start   "
                , span [ class "znak cel" ] [ text "C" ], text " cel"
                ]
            , div [ class "przyciski" ]
                [ button [ type_ "button", onClick (IdzDo StronaAuta) ] [ text "Zobacz auta" ]
                , button [ type_ "button", class "drugi", onClick (OtworzOpinie k.id) ] [ text "Opinie o tym aucie" ]
                , button [ type_ "button", class "drugi", onClick NoweZamowienie ] [ text "Nowe zamówienie" ]
                ]
            ]

        _ ->
            let
                wysylanie =
                    z.stan == ZamWysylanie
            in
            [ h1 [] [ text "Zamów przejazd" ]
            , p [ class "szary" ] [ text "Wybierz punkt i kliknij na mapie albo wpisz współrzędne." ]
            , div [ class "przelacznik" ]
                [ przelacznik z Start "Ustawiam start"
                , przelacznik z Cel "Ustawiam cel"
                ]
            , mapa True s.kierowcy (punktyZamowienia z)
            , form [ onSubmit Zamow ]
                [ div [ class "wsp" ]
                    [ poleWsp "Start: szerokość" "slat" z.startLat StartLat
                    , poleWsp "Start: długość" "slon" z.startLon StartLon
                    , poleWsp "Cel: szerokość" "clat" z.celLat CelLat
                    , poleWsp "Cel: długość" "clon" z.celLon CelLon
                    ]
                , label [ for "miejsca" ] [ text "Liczba miejsc" ]
                , select [ id "miejsca", onInput WpisanoMiejsca ]
                    (List.map
                        (\n ->
                            option
                                [ value (String.fromInt n), selected (String.fromInt n == z.miejsca) ]
                                [ text (String.fromInt n) ]
                        )
                        [ 1, 2, 3, 4 ]
                    )
                , case z.stan of
                    ZamPisanie (Just tresc) ->
                        p [ class "blad" ] [ text tresc ]

                    _ ->
                        text ""
                , button [ type_ "submit", disabled wysylanie ]
                    [ text
                        (if wysylanie then
                            "Wysyłanie…"

                         else
                            "Zamów"
                        )
                    ]
                ]
            ]


przelacznik : FormZamowienia -> Punkt -> String -> Html Msg
przelacznik z punkt napis =
    button
        [ type_ "button"
        , classList [ ( "zakladka", True ), ( "aktywna", z.ustawiam == punkt ) ]
        , onClick (UstawPunkt punkt)
        ]
        [ text napis ]


poleWsp : String -> String -> String -> Pole -> Html Msg
poleWsp etykieta idPola wartosc p =
    div []
        [ label [ for idPola ] [ text etykieta ]
        , input
            [ id idPola
            , type_ "text"
            , attribute "inputmode" "decimal"
            , required True
            , value wartosc
            , onInput (WpisanoWsp p)
            ]
            []
        ]


{-| punkty wpisane w formularzu, o ile da się je odczytać jako liczby
-}
punktyZamowienia : FormZamowienia -> List Znacznik
punktyZamowienia z =
    List.filterMap identity
        [ Maybe.map2 (\a b -> Znacznik "start" a b "S") (parsuj z.startLat) (parsuj z.startLon)
        , Maybe.map2 (\a b -> Znacznik "cel" a b "C") (parsuj z.celLat) (parsuj z.celLon)
        ]



-- opinie


widokOpinii : Sesja -> List (Html Msg)
widokOpinii s =
    let
        k =
            s.kom
    in
    [ h1 [] [ text "Opinie o kierowcach" ]
    , label [ for "auto" ] [ text "Auto" ]
    , select [ id "auto", onInput WybranoKierowce ]
        (option [ value "", selected (k.wybrany == Nothing) ] [ text "Wybierz auto…" ]
            :: List.map
                (\a -> option [ value a.id, selected (k.wybrany == Just a.id) ] [ text ("Auto #" ++ a.id) ])
                s.kierowcy
        )
    , case k.lista of
        ListaPusta ->
            p [ class "szary" ] [ text "Wybierz auto, aby zobaczyć opinie." ]

        ListaLaduje ->
            p [ class "szary" ] [ text "Ładowanie…" ]

        ListaBlad ->
            p [ class "blad" ] [ text "Nie udało się pobrać opinii." ]

        ListaGotowa [] ->
            p [ class "szary" ] [ text "Brak opinii o tym aucie." ]

        ListaGotowa lista ->
            div [] (List.map widokOpinii1 lista)
    , case k.wybrany of
        Just _ ->
            formularzOpinii k

        Nothing ->
            text ""
    ]


widokOpinii1 : Komentarz -> Html Msg
widokOpinii1 o =
    div [ class "opinia" ]
        [ div [ class "naglowek" ]
            [ span [ class "gwiazdki" ] [ text (gwiazdki o.ocena) ]
            , span [ class "szary" ] [ text (ukryjEmail o.autor ++ " · " ++ String.left 16 o.data) ]
            ]
        , p [] [ text o.tresc ]
        ]


gwiazdki : Float -> String
gwiazdki ocena =
    let
        n =
            clamp 0 5 (round ocena)
    in
    String.repeat n "★" ++ String.repeat (5 - n) "☆"


{-| backend zwraca pełne e-maile autorów; na ekranie pokazujemy tylko "a***@domena"
-}
ukryjEmail : String -> String
ukryjEmail email =
    case String.split "@" email of
        [ lewa, domena ] ->
            String.left 1 lewa ++ "***@" ++ domena

        _ ->
            "***"


formularzOpinii : FormKomentarzy -> Html Msg
formularzOpinii k =
    form [ class "nowa-opinia", onSubmit WystawKomentarz ]
        [ h1 [ class "podtytul" ] [ text "Dodaj opinię" ]
        , label [ for "ocena" ] [ text "Ocena" ]
        , select [ id "ocena", onInput WpisanoOcene ]
            (List.map
                (\n ->
                    option
                        [ value (String.fromInt n), selected (String.fromInt n == k.ocena) ]
                        [ text (String.fromInt n ++ " " ++ gwiazdki (toFloat n)) ]
                )
                [ 5, 4, 3, 2, 1 ]
            )
        , label [ for "tresc" ] [ text "Treść" ]
        , textarea
            [ id "tresc"
            , rows 4
            , maxlength 500
            , required True
            , value k.tresc
            , onInput WpisanoTresc
            ]
            []
        , case k.blad of
            Just tresc ->
                p [ class "blad" ] [ text tresc ]

            Nothing ->
                text ""
        , case k.info of
            Just tresc ->
                p [ class "info" ] [ text tresc ]

            Nothing ->
                text ""
        , button [ type_ "submit", disabled k.wysylanie ]
            [ text
                (if k.wysylanie then
                    "Wysyłanie…"

                 else
                    "Dodaj opinię"
                )
            ]
        ]



-- logowanie i rejestracja


formularz : Model -> Bool -> Maybe String -> List (Html Msg)
formularz model wysylanie blad =
    let
        rejestracja =
            model.tryb == Rejestracja

        napis logowanie rejestr =
            if rejestracja then
                rejestr

            else
                logowanie
    in
    [ h1 [] [ text (napis "Logowanie" "Rejestracja") ]
    , form [ onSubmit (napis Zaloguj Zarejestruj) ]
        ([ label [ for "email" ] [ text "E-mail" ]
         , input
            [ id "email"
            , type_ "email"
            , autocomplete True
            , required True
            , value model.email
            , onInput WpisanoEmail
            ]
            []
         , label [ for "haslo" ] [ text "Hasło" ]
         , input
            [ id "haslo"
            , type_ "password"
            , required True
            , value model.haslo
            , onInput WpisanoHaslo
            ]
            []
         ]
            ++ (if rejestracja then
                    [ label [ for "powtorz" ] [ text "Powtórz hasło" ]
                    , input
                        [ id "powtorz"
                        , type_ "password"
                        , required True
                        , value model.powtorz
                        , onInput WpisanoPowtorz
                        ]
                        []
                    ]

                else
                    []
               )
            ++ [ case blad of
                    Just tresc ->
                        p [ class "blad" ] [ text tresc ]

                    Nothing ->
                        text ""
               , button [ type_ "submit", disabled wysylanie ]
                    [ text
                        (if wysylanie then
                            napis "Logowanie…" "Rejestrowanie…"

                         else
                            napis "Zaloguj się" "Zarejestruj się"
                        )
                    ]
               ]
        )
    , button [ type_ "button", class "link", disabled wysylanie, onClick PrzelaczTryb ]
        [ text (napis "Nie masz konta? Zarejestruj się" "Masz już konto? Zaloguj się") ]
    ]
