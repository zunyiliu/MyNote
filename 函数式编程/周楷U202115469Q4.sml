fun quickSort([]: int list) = []  
  | quickSort(xs: int list) =
    let
      fun partition([], less, greater) = (less, greater)  
        | partition(x::xs, less, greater) =
          if x <= hd(xs)
          then partition(xs, x::less, greater)  
          else partition(xs, less, x::greater)  
      
      val (less, greater) = partition(tl(xs), [], [])  
    in
      quickSort(less) @ [hd(xs)] @ quickSort(greater)  
    end;