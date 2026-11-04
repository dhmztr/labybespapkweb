module View.Konto exposing (..)

import Html exposing (Html, button, div, form, h2, input, label, p, section, text)
import Html.Attributes exposing (attribute, autocomplete, class, classList, disabled, for, id, required, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Types exposing (..)
import Format exposing (wejscie)
import Bledy exposing (minDlugoscHasla)


sekcjaKonto : Model -> Html Msg
sekcjaKonto model =
    section [ id "konto", class "sekcja konto" ]
        [ div [ class "konto__tekst" ]
            [ h2 (class "konto__tytul" :: wejscie 0) [ text "Jedno konto, cały Wrocław" ]
            , p (class "konto__opis" :: wejscie 1)
                [ text "Wystarczy e-mail i hasło. Po zalogowaniu widzisz całą flotę na mapie 3D, zamawiasz przejazd jednym kliknięciem i oceniasz kierowców." ]
            ]
        , div (class "konto__panel" :: attribute "data-ui" "" :: wejscie 2) (panelKonta model)
        ]


panelKonta : Model -> List (Html Msg)
panelKonta model =
    let
        rejestracja =
            model.tryb == Rejestracja

        wysylanie =
            model.stan == Wysylanie

        napis logowanie rejestr =
            if rejestracja then
                rejestr

            else
                logowanie
    in
    [ div [ class "segment", attribute "role" "group", attribute "aria-label" "Rodzaj formularza" ]
        [ przyciskSegmentu (not rejestracja) (UstawTryb Logowanie) "Logowanie"
        , przyciskSegmentu rejestracja (UstawTryb Rejestracja) "Rejestracja"
        ]
    , case model.stan of
        Sprawdzanie ->
            p [ class "komunikat" ] [ text "Sprawdzanie zapamiętanej sesji…" ]

        Wylogowany ->
            p [ class "komunikat komunikat--ok" ] [ text "Wylogowano. Do zobaczenia na trasie." ]

        _ ->
            text ""
    , form [ class "formularz", onSubmit (napis Zaloguj Zarejestruj) ]
        ([ label [ for "email" ] [ text "E-mail" ]
         , input
            [ id "email"
            , type_ "email"
            , autocomplete True
            , attribute "autocomplete" "email"
            , required True
            , value model.email
            , onInput WpisanoEmail
            ]
            []
         , label [ for "haslo" ] [ text "Hasło" ]
         , input
            [ id "haslo"
            , type_ "password"
            , attribute "autocomplete" (napis "current-password" "new-password")
            , required True
            , attribute "minlength" (napis "" (String.fromInt minDlugoscHasla))
            , value model.haslo
            , onInput WpisanoHaslo
            ]
            []
         ]
            ++ (if rejestracja then
                    [ p [ class "podpowiedz" ]
                        [ text ("Hasło: minimum " ++ String.fromInt minDlugoscHasla ++ " znaków.") ]
                    , label [ for "powtorz" ] [ text "Powtórz hasło" ]
                    , input
                        [ id "powtorz"
                        , type_ "password"
                        , attribute "autocomplete" "new-password"
                        , required True
                        , value model.powtorz
                        , onInput WpisanoPowtorz
                        ]
                        []
                    ]

                else
                    []
               )
            ++ [ case model.stan of
                    Formularz (Just tresc) ->
                        p [ class "blad", attribute "role" "alert" ] [ text tresc ]

                    _ ->
                        text ""
               , button [ type_ "submit", class "przycisk przycisk--pelny", disabled wysylanie ]
                    [ text
                        (if wysylanie then
                            napis "Logowanie…" "Rejestrowanie…"

                         else
                            napis "Zaloguj się" "Załóż konto"
                        )
                    ]
               ]
        )
    ]


przyciskSegmentu : Bool -> Msg -> String -> Html Msg
przyciskSegmentu aktywny msg napis =
    button
        [ type_ "button"
        , classList [ ( "segment__opcja", True ), ( "segment__opcja--aktywna", aktywny ) ]
        , attribute "aria-pressed"
            (if aktywny then
                "true"

             else
                "false"
            )
        , onClick msg
        ]
        [ text napis ]
