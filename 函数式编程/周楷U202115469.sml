fun subsetSumOption(L, s) =
          let fun SubsetSumOptionHelper([], 0) = true
                    | SubsetSumOptionHelper([], _) = false
                    | SubsetSumOptionHelper(l::ls, sum) = SubsetSumOptionHelper(ls, sum-l) orelse SubsetSumOptionHelper(ls, sum)
          in if SubsetSumOptionHelper(L, s) then SOME L else NONE
          end