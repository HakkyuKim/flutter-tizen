import sys
import os
import json
import yaml
from collections import OrderedDict

if __name__ == "__main__":
    arg = sys.argv
    for path in sys.argv[1:]:
        if not os.path.exists(path):
            print('no file')
            exit(1)
        with open(path) as f:
            data = json.load(f, object_pairs_hook=OrderedDict)

        yaml.add_representer(OrderedDict, lambda dumper, data: dumper.represent_mapping(
            'tag:yaml.org,2002:map', data.items()))
        def represent_none(self, _):
            return self.represent_scalar('tag:yaml.org,2002:null', '')
        yaml.add_representer(type(None), represent_none)

        with open(path.replace('.json', '.yaml'), 'w') as f:
            yaml.dump(data, f)
