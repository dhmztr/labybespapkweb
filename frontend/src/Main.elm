module Main exposing (main)

import Browser
import Html exposing (Html, button, div, form, h1, input, label, p, text)
import Html.Attributes exposing (autocomplete, class, disabled, for, id, required, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Json.Decode as D
import Json.Encode as E


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> ( poczatek, Cmd.none )
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }



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
    | Zalogowany { email : String, token : String }


poczatek : Model
poczatek =
    { email = "", haslo = "", powtorz = "", tryb = Logowanie, stan = Formularz Nothing }



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
    | Wyloguj


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
            ( { model | haslo = "", powtorz = "", stan = Zalogowany { email = email, token = token } }, Cmd.none )

        OdpowiedzJa _ (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        Wyloguj ->
            ( poczatek, Cmd.none )


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
        , headers = [ Http.header "Authorization" token ]
        , url = "/ja"
        , body = Http.emptyBody
        , expect = Http.expectJson (OdpowiedzJa token) D.string
        , timeout = Nothing
        , tracker = Nothing
        }



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "karta" ]
        (case model.stan of
            Zalogowany dane ->
                [ h1 [] [ text "Witaj!" ]
                , p [] [ text ("Zalogowano jako " ++ dane.email) ]
                , button [ onClick Wyloguj ] [ text "Wyloguj" ]
                ]

            Formularz blad ->
                formularz model False blad

            Wysylanie ->
                formularz model True Nothing
        )


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
