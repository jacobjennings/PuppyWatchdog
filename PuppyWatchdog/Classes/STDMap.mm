//
//  STDMap.mm
//  PuppyWatchdog
//
//  Copyright (c) 2016 Machine Learning Works
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#include <map>

#import "STDMap.h"

@implementation STDMap {
  @public
    std::map<void *, id> _map;
}

@end

extern "C" {

id STDMapGet(STDMap *m, void *key) {
    auto it = m->_map.find(key);
    if (it == m->_map.end()) {
        return nil;
    }
    return it->second;
}

id STDMapGetLessOrEqual(STDMap *m, void *key, void **outKey) {
    auto iter = m->_map.lower_bound(key);
    if (iter == m->_map.end()) {
        return nil;
    }

    if (iter->first != key && iter != m->_map.begin()) {
        --iter;
    }

    *outKey = iter->first;
    return iter->second;
}

void STDMapInsert(STDMap *m, void *key, id value) {
    m->_map.insert(std::make_pair(key, value));
}

void STDMapRemove(STDMap *m, void *key) {
    m->_map.erase(key);
}

} // extern "C"
