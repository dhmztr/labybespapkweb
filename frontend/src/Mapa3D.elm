module Mapa3D exposing (..)

import Html exposing (Html, img, label, node)
import Html.Attributes exposing (attribute, class, id)
import Json.Encode as E
import Types exposing (..)
import Klasy exposing (Klasa)


-- 3D
-- <unter-auto> i <unter-miasto> to custom elementy z public/unter3d.js (Three.js);
-- dane dostają w atrybutach jako JSON, kliknięcia oddają zdarzeniami


flotaJson : List Kierowca -> String
flotaJson flota =
    E.encode 0
        (E.list
            (\k ->
                E.object
                    [ ( "id", E.string k.id )
                    , ( "lat", E.float k.lat )
                    , ( "lon", E.float k.lon )
                    , ( "wolne", E.int k.wolne )
                    , ( "cel", punktJson k.cel )
                    , ( "celKoncowy", punktJson k.celKoncowy )
                    ]
            )
            flota
        )


punktJson : Maybe ( Float, Float ) -> E.Value
punktJson punkt =
    case punkt of
        Just ( la, lo ) ->
            E.list E.float [ la, lo ]

        Nothing ->
            E.null


punktyJson : List Znacznik -> String
punktyJson punkty =
    E.encode 0
        (E.list
            (\z ->
                E.object
                    [ ( "rodzaj", E.string z.klasa )
                    , ( "lat", E.float z.lat )
                    , ( "lon", E.float z.lon )
                    ]
            )
            punkty
        )


auto3d : String -> Klasa -> Bool -> Html Msg
auto3d klasaCss k wolne =
    node "unter-auto"
        [ class klasaCss
        , attribute "model" k.kod
        , attribute "wolne"
            (if wolne then
                "tak"

             else
                "nie"
            )
        , attribute "role" "img"
        , attribute "aria-label" ("Model 3D auta klasy " ++ k.nazwa ++ ". Przeciągnij, aby obrócić.")
        ]
        []
