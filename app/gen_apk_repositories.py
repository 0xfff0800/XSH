import os

def trim(x, start, end):
    assert x.startswith(start)
    assert x.endswith(end)
    return x[len(start):-len(end)]

APK_REPOSITORIES = [
    ('v3.14', 'main'),
    ('v3.14', 'community'),
]
ARCH = 'x86' # TODO: support more archs

repos_file = []
repos_file.append('http://apk.ish.app/v3.14-2023-05-19/main')
repos_file.append('http://apk.ish.app/v3.14-2023-05-19/community')

with open(os.path.join(os.environ['BUILT_PRODUCTS_DIR'], os.environ['CONTENTS_FOLDER_PATH'], 'repositories.txt'), 'w') as f:
    for line in repos_file:
        print(line, file=f)
