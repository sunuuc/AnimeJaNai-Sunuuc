"""Check source publication with and without generated file changes."""
from pathlib import Path
import ast
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SourceTreeTests(unittest.TestCase):
    def prune(self,current,releases,failed=False):
        source=ast.parse((ROOT/'tools/standalone/publish.py').read_text(encoding='utf-8'))
        function=next(node for node in source.body if isinstance(node,ast.FunctionDef) and node.name=='prune_previous_releases')
        remaining=[dict(r) for r in releases];deleted=[]
        def api(endpoint,payload=None,method=None):
            if method=='DELETE':
                if failed:raise RuntimeError('Deletion failed')
                release_id=int(endpoint.rsplit('/',1)[1]);deleted.append(release_id)
                remaining[:]=[r for r in remaining if r['id']!=release_id]
            else:return list(remaining)
        scope={'REPO':'owner/project','api':api}
        exec(compile(ast.Module(body=[function],type_ignores=[]),'publish.py','exec'),scope)
        result=scope['prune_previous_releases'](current)
        return result,deleted,remaining

    def test_pruning_leaves_only_current_release_and_removes_old_drafts(self):
        current={'id':2,'tag_name':'new','draft':False}
        old={'id':1,'tag_name':'old','draft':False};draft={'id':3,'tag_name':'draft','draft':True}
        removed,deleted,remaining=self.prune(current,[old,current,draft])
        self.assertEqual(removed,['old','draft']);self.assertEqual(deleted,[1,3]);self.assertEqual(remaining,[current])

    def test_pruning_requires_the_current_public_release(self):
        with self.assertRaisesRegex(RuntimeError,'Cannot prune'):
            self.prune({'id':1,'draft':True},[{'id':1,'draft':True}])
        with self.assertRaisesRegex(RuntimeError,'Cannot prune'):
            self.prune({'id':1,'draft':False},[])

    def test_pruning_surfaces_delete_failures(self):
        with self.assertRaisesRegex(RuntimeError,'Deletion failed'):
            self.prune({'id':2,'draft':False},[{'id':1,'draft':False},{'id':2,'draft':False}],failed=True)

    def build_tree(self, changes, api):
        source = ast.parse((ROOT / 'tools/standalone/publish.py').read_text(encoding='utf-8'))
        assignment = next(node for node in source.body if isinstance(node, ast.Assign)
                          and any(isinstance(target, ast.Name) and target.id == 'newtree'
                                  for target in node.targets))
        scope = {'tree': changes, 'base_tree': 'existing-tree', 'REPO': 'owner/project', 'api': api}
        exec(compile(ast.Module(body=[assignment], type_ignores=[]), 'publish.py', 'exec'), scope)
        return scope['newtree']

    def test_unchanged_sources_reuse_tree_without_empty_api_request(self):
        def unexpected(*args):
            self.fail('GitHub rejects an empty tree update')
        self.assertEqual(self.build_tree([], unexpected), 'existing-tree')

    def test_changed_sources_create_tree(self):
        changes = [{'path': 'file.txt', 'mode': '100644', 'type': 'blob', 'content': 'changed'}]
        def api(endpoint, payload):
            self.assertEqual(endpoint, 'repos/owner/project/git/trees')
            self.assertEqual(payload, {'base_tree': 'existing-tree', 'tree': changes})
            return {'sha': 'updated-tree'}
        self.assertEqual(self.build_tree(changes, api), 'updated-tree')

    def test_changed_sources_do_not_ignore_api_failure(self):
        def api(*args):
            raise RuntimeError('request failed')
        with self.assertRaisesRegex(RuntimeError, 'request failed'):
            self.build_tree([{'path': 'file.txt'}], api)

if __name__ == '__main__':
    unittest.main()
