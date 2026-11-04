module View.Opinie exposing (..)

import Html exposing (Html, a, button, div, form, h1, h2, label, option, p, select, span, text, textarea)
import Html.Attributes exposing (attribute, class, classList, disabled, for, id, maxlength, required, rows, selected, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Types exposing (..)
import Klasy exposing (klasaAuta)
import Format exposing (jednoMiejsce)


-- opinie


widokOpinii : List Kierowca -> Sesja -> List (Html Msg)
widokOpinii flota s =
    let
        k =
            s.kom
    in
    [ h1 [ class "panel__tytul" ] [ text "Opinie o kierowcach" ]
    , if List.isEmpty s.doOceny then
        text ""

      else
        div [ class "do-oceny" ]
            (p [ class "etykieta" ] [ text "Czekają na Twoją ocenę" ]
                :: List.map
                    (\id -> button [ type_ "button", class "przycisk-drugi", onClick (WybranoKierowce id) ] [ text ("Auto #" ++ id) ])
                    s.doOceny
            )
    , div [ class "pole" ]
        [ label [ for "auto" ] [ text "Auto" ]
        , select [ id "auto", onInput WybranoKierowce ]
            (option [ value "", selected (k.wybrany == Nothing) ] [ text "Wybierz auto…" ]
                :: List.map
                    (\a -> option [ value a.id, selected (k.wybrany == Just a.id) ] [ text ("#" ++ a.id ++ " · " ++ (klasaAuta a).nazwa) ])
                    (List.filter (\a -> List.member a.id s.doOceny || k.wybrany == Just a.id) flota)
            )
        ]
    , case k.lista of
        ListaPusta ->
            p [ class "podpowiedz" ] [ text "Wybierz auto z listy albo kliknij je na mapie." ]

        ListaLaduje ->
            p [ class "podpowiedz" ] [ text "Ładowanie opinii…" ]

        ListaBlad ->
            p [ class "blad" ] [ text "Nie udało się pobrać opinii." ]

        ListaGotowa [] ->
            p [ class "podpowiedz" ] [ text "Nikt jeszcze nie ocenił tego auta. Twoja opinia będzie pierwsza." ]

        ListaGotowa lista ->
            div [ class "opinie" ]
                (p [ class "opinie__srednia" ]
                    [ text
                        ("Średnia "
                            ++ jednoMiejsce (List.sum (List.map .ocena lista) / toFloat (List.length lista))
                            ++ " z "
                            ++ String.fromInt (List.length lista)
                            ++ " opinii"
                        )
                    ]
                    :: List.map widokOpinii1 lista
                )
    , case k.wybrany of
        Just id ->
            if List.member id s.doOceny then
                formularzOpinii k

            else if k.info /= Nothing then
                p [ class "komunikat komunikat--ok" ] [ text (Maybe.withDefault "" k.info) ]

            else if s.przejazd == Just id then
                p [ class "podpowiedz podpowiedz--ramka" ] [ text "Jedziesz teraz tym autem. Opinię wystawisz, gdy przejazd się zakończy." ]

            else
                p [ class "podpowiedz podpowiedz--ramka" ] [ text "Opinię wystawisz po zakończonym przejeździe tym autem." ]

        Nothing ->
            text ""
    ]


widokOpinii1 : Komentarz -> Html Msg
widokOpinii1 o =
    div [ class "opinia" ]
        [ div [ class "opinia__naglowek" ]
            [ span [ class "gwiazdki", attribute "aria-label" ("Ocena " ++ String.fromInt (round o.ocena) ++ " na 5") ] [ text (gwiazdki o.ocena) ]
            , span [ class "opinia__autor" ] [ text (ukryjEmail o.autor ++ " · " ++ String.left 16 o.data) ]
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
    let
        wybrana =
            Maybe.withDefault 5 (String.toInt k.ocena)
    in
    form [ class "formularz nowa-opinia", onSubmit WystawKomentarz ]
        [ h2 [ class "panel__podtytul" ] [ text "Dodaj opinię" ]
        , p [ class "etykieta", id "ocena-etykieta" ] [ text "Ocena" ]
        , div [ class "ocena", attribute "role" "group", attribute "aria-labelledby" "ocena-etykieta" ]
            (List.map
                (\n ->
                    button
                        [ type_ "button"
                        , classList [ ( "ocena__gwiazdka", True ), ( "ocena__gwiazdka--pelna", n <= wybrana ) ]
                        , attribute "aria-label" (String.fromInt n ++ " na 5")
                        , attribute "aria-pressed"
                            (if n == wybrana then
                                "true"

                             else
                                "false"
                            )
                        , onClick (WpisanoOcene (String.fromInt n))
                        ]
                        [ text "★" ]
                )
                [ 1, 2, 3, 4, 5 ]
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
                p [ class "blad", attribute "role" "alert" ] [ text tresc ]

            Nothing ->
                text ""
        , case k.info of
            Just tresc ->
                p [ class "komunikat komunikat--ok" ] [ text tresc ]

            Nothing ->
                text ""
        , button [ type_ "submit", class "przycisk przycisk--ciemny przycisk--pelny", disabled k.wysylanie ]
            [ text
                (if k.wysylanie then
                    "Wysyłanie…"

                 else
                    "Dodaj opinię"
                )
            ]
        ]
