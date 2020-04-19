func appendTo<S, T>(dict : inout [S : [T]], key : S, value : T) {
    if var values = dict[key] {
        values.append(value)
        dict[key] = values
    } else {
        dict[key] = [value]
    }
}

@discardableResult
func insertTo<S, T>(dict : inout [S : Set<T>], key : S, value : T) -> Bool {
    if var values = dict[key] {
        if values.insert(value).inserted {
            dict[key] = values
            return true
        } else {
            return false
        }
    } else {
        dict[key] = [value]
        return true
    }
}

@discardableResult
func insertTo<S, T>(dict : inout [S : Set<T>], key : S, values : Set<T>) -> Bool {
    if values.isEmpty { return false }
    if var oldValues = dict[key] {
        let oldSize = oldValues.count
        oldValues.formUnion(values)
        dict[key] = oldValues
        return oldValues.count != oldSize
    } else {
        dict[key] = values
        return true
    }
}

@discardableResult
func insertTo<S, T>(dict : inout [S : Set<T>], _ other : [S : Set<T>]) -> Bool {
    var changed = false
    for (key, values) in other {
        if insertTo(dict: &dict, key: key, values: values) {
            changed = true
        }
    }
    return changed
}
