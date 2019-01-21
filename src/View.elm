module View exposing (view)

import Browser
import Element as El exposing (Element)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Model exposing (..)


view : Model -> Browser.Document Msg
view model =
    { title = "MBTA Stop Predictions - skyqrose"
    , body =
        [ El.layout [] (ui model) ]
    }


ui : Model -> Element Msg
ui model =
    El.column
        [ El.padding unit
        , El.spacing unit
        ]
        [ El.text "Stops"
        , El.column
            [ El.spacing unit
            ]
            (List.map viewStop model.stops)
        , addStopForm model
        ]


viewStop : ( Stop, PredictionsForStop ) -> Element msg
viewStop ( stop, predictions ) =
    El.row
        [ Border.width 1
        , Border.rounded 4
        , El.padding unit
        ]
        [ El.column
            [ El.alignLeft
            ]
            [ El.text stop.routeId
            , El.el
                [ Font.size fontSmall
                ]
                (El.text stop.stopId)
            ]
        , El.column
            [ El.alignRight
            ]
            (case predictions of
                Loading ->
                    [ El.text "Loading" ]

                _ ->
                    [ El.text "Predictions" ]
            )
        ]


addStopForm : Model -> Element Msg
addStopForm model =
    El.column
        [ El.spacing unit
        ]
        [ Input.text []
            { onChange = TypeRouteId
            , text = model.routeIdFormText
            , placeholder = Nothing
            , label = label "Route Id"
            }
        , Input.text []
            { onChange = TypeStopId
            , text = model.stopIdFormText
            , placeholder = Nothing
            , label = label "Stop Id"
            }
        , Input.button []
            { onPress =
                Just
                    (AddStop
                        { routeId = model.routeIdFormText
                        , stopId = model.stopIdFormText
                        }
                    )
            , label = El.text "Add Stop"
            }
        ]


label : String -> Input.Label msg
label text =
    Input.labelAbove [] (El.text text)


{-| Pixels
-}
unit : Int
unit =
    16


fontSmall : Int
fontSmall =
    14
