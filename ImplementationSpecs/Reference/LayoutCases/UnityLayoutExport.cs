//
// Created by Codex on 15.11.2026.
//

// Copy into Assets/Editor of a separate Unity 6000.0.26f1 project.
#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.UI;

namespace LayoutConformance
{
    [Serializable] public class Document { public Suite Root; }
    [Serializable] public class Suite { public int schemaVersion; public Case[] cases; }
    [Serializable] public class Case { public string id; public Node[] nodes; public Change[] changes; }
    [Serializable] public class RectData {
        public Vector2 anchorMin, anchorMax, pivot, position, size;
        public Vector3 scale;
    }
    [Serializable] public class Node {
        public bool hasRect, hasActive, hasGroup, hasGrid, hasFitter, hasAspect, hasReflow, hasElements;
        public int parent = -1;
        public bool active = true;
        public RectData rect;
        public Group group;
        public Grid grid;
        public Fitter fitter;
        public Aspect aspect;
        public Reflow reflow;
        public Element[] elements;
    }
    [Serializable] public class Change : Node {
        public int node;
        public bool hasTargetParent, hasSiblingIndex;
        public int targetParent = -1, siblingIndex = -1;
    }
    [Serializable] public class Group {
        public string direction, childAlignHorizontal, childAlignVertical;
        public float spacing, paddingLeft, paddingRight, paddingTop, paddingBottom;
        public bool controlChildWidth, controlChildHeight, childForceExpandWidth, childForceExpandHeight;
        public bool childScaleWidth, childScaleHeight, reverseArrangement;
    }
    [Serializable] public class Grid {
        public string startCorner, startAxis, constraint;
        public int constraintCount, childAlignment;
        public Vector2 cellSize, spacing, paddingMin, paddingMax;
    }
    [Serializable] public class Fitter { public string horizontalFit, verticalFit; }
    [Serializable] public class Aspect { public string mode; public float aspectRatio; }
    [Serializable] public class Reflow { public int glyphCount; public float glyphWidth, lineHeight; }
    [Serializable] public class Element {
        public bool ignoreLayout;
        public float minWidth, minHeight, preferredWidth, preferredHeight, flexibleWidth, flexibleHeight;
        public int layoutPriority;
    }
    public class SyntheticMetrics : MonoBehaviour, ILayoutElement {
        public Reflow data;
        private float height;
        public void CalculateLayoutInputHorizontal() { }
        public void CalculateLayoutInputVertical() {
            float columns = Mathf.Max(1, Mathf.Floor(((RectTransform)transform).rect.width / Mathf.Max(.001f, data.glyphWidth)));
            height = Mathf.Max(1, Mathf.Ceil(data.glyphCount / columns)) * data.lineHeight;
        }
        public float minWidth => data.glyphWidth;
        public float preferredWidth => data.glyphCount * data.glyphWidth;
        public float flexibleWidth => -1;
        public float minHeight => data.lineHeight;
        public float preferredHeight => height;
        public float flexibleHeight => -1;
        public int layoutPriority => 0;
    }
    [Serializable] public class ResultDocument { public Results Root = new Results(); }
    [Serializable] public class Results { public List<CaseResult> cases = new List<CaseResult>(); }
    [Serializable] public class CaseResult { public string id; public List<State> states = new List<State>(); }
    [Serializable] public class State { public List<NodeResult> nodes = new List<NodeResult>(); }
    [Serializable] public class NodeResult {
        public Vector2 corner0, corner1, corner2, corner3;
        public Vector2 rectMin, rectSize, anchorMin, anchorMax, pivot, position, sizeDelta, offsetMin, offsetMax;
        public Vector3 scale;
        public float minWidth, preferredWidth, flexibleWidth, minHeight, preferredHeight, flexibleHeight;
    }
    public static class UnityLayoutExport {
        private static T Parse<T>(string value) where T : struct => (T)Enum.Parse(typeof(T), value);
        private static void Apply(RectTransform r, Node n, bool create) {
            if (n.hasRect) {
                r.anchorMin = n.rect.anchorMin;
                r.anchorMax = n.rect.anchorMax;
                r.pivot = n.rect.pivot;
                r.sizeDelta = n.rect.size;
                r.anchoredPosition = n.rect.position;
                r.localScale = n.rect.scale;
            }
            if (n.hasActive) r.gameObject.SetActive(n.active);
            if (n.hasGroup) {
                var d = n.group;
                var g = create ? (d.direction == "Horizontal" ? (HorizontalOrVerticalLayoutGroup)r.gameObject.AddComponent<HorizontalLayoutGroup>() : r.gameObject.AddComponent<VerticalLayoutGroup>()) : r.GetComponent<HorizontalOrVerticalLayoutGroup>();
                int x = Array.IndexOf(new[] { "Left", "Center", "Right" }, d.childAlignHorizontal);
                int y = Array.IndexOf(new[] { "Upper", "Middle", "Lower" }, d.childAlignVertical);
                if (x < 0 || y < 0)
                    throw new InvalidDataException("Invalid alignment: horizontal='" + d.childAlignHorizontal + "', vertical='" + d.childAlignVertical + "'");
                g.childAlignment = (TextAnchor)(y * 3 + x);
                g.padding = new RectOffset((int)d.paddingLeft, (int)d.paddingRight, (int)d.paddingTop, (int)d.paddingBottom);
                g.spacing = d.spacing;
                g.childControlWidth = d.controlChildWidth;
                g.childControlHeight = d.controlChildHeight;
                g.childForceExpandWidth = d.childForceExpandWidth;
                g.childForceExpandHeight = d.childForceExpandHeight;
                g.childScaleWidth = d.childScaleWidth;
                g.childScaleHeight = d.childScaleHeight;
                g.reverseArrangement = d.reverseArrangement;
            }
            if (n.hasGrid) {
                var d = n.grid;
                var g = create ? r.gameObject.AddComponent<GridLayoutGroup>() : r.GetComponent<GridLayoutGroup>();
                g.startCorner = Parse<GridLayoutGroup.Corner>(d.startCorner);
                g.startAxis = Parse<GridLayoutGroup.Axis>(d.startAxis);
                g.constraint = Parse<GridLayoutGroup.Constraint>(d.constraint);
                g.constraintCount = d.constraintCount;
                g.cellSize = d.cellSize;
                g.spacing = d.spacing;
                g.padding = new RectOffset((int)d.paddingMin.x, (int)d.paddingMax.x, (int)d.paddingMin.y, (int)d.paddingMax.y);
                g.childAlignment = (TextAnchor)d.childAlignment;
            }
            if (n.hasFitter) {
                var g = create ? r.gameObject.AddComponent<ContentSizeFitter>() : r.GetComponent<ContentSizeFitter>();
                g.horizontalFit = Parse<ContentSizeFitter.FitMode>(n.fitter.horizontalFit);
                g.verticalFit = Parse<ContentSizeFitter.FitMode>(n.fitter.verticalFit);
            }
            if (n.hasAspect) {
                var g = create ? r.gameObject.AddComponent<AspectRatioFitter>() : r.GetComponent<AspectRatioFitter>();
                g.aspectMode = Parse<AspectRatioFitter.AspectMode>(n.aspect.mode);
                g.aspectRatio = n.aspect.aspectRatio;
            }
            if (n.hasReflow) {
                var g = create ? r.gameObject.AddComponent<SyntheticMetrics>() : r.GetComponent<SyntheticMetrics>();
                g.data = n.reflow;
            }
            if (n.hasElements) {
                if (!create) throw new InvalidDataException("Dynamic element replacement unsupported");
                foreach (var d in n.elements) {
                    var g = r.gameObject.AddComponent<LayoutElement>();
                    g.ignoreLayout = d.ignoreLayout;
                    g.minWidth = d.minWidth;
                    g.minHeight = d.minHeight;
                    g.preferredWidth = d.preferredWidth;
                    g.preferredHeight = d.preferredHeight;
                    g.flexibleWidth = d.flexibleWidth;
                    g.flexibleHeight = d.flexibleHeight;
                    g.layoutPriority = d.layoutPriority;
                }
            }
        }
        private static void Rebuild(RectTransform[] nodes) {
            LayoutRebuilder.ForceRebuildLayoutImmediate(nodes[0]);
            for (int i = 1; i < nodes.Length; ++i) {
                var parent = nodes[i].parent;
                if (parent == null || parent.GetComponents<ILayoutController>().Length == 0)
                    LayoutRebuilder.ForceRebuildLayoutImmediate(nodes[i]);
            }
        }
        private static NodeResult Capture(RectTransform r) {
            var corners = new Vector3[4];
            r.GetWorldCorners(corners);
            return new NodeResult {
                corner0 = corners[0], corner1 = corners[1], corner2 = corners[2], corner3 = corners[3],
                rectMin = r.rect.min, rectSize = r.rect.size, anchorMin = r.anchorMin,
                anchorMax = r.anchorMax, pivot = r.pivot, position = r.anchoredPosition,
                sizeDelta = r.sizeDelta, offsetMin = r.offsetMin, offsetMax = r.offsetMax,
                scale = r.localScale, minWidth = LayoutUtility.GetMinWidth(r),
                preferredWidth = LayoutUtility.GetPreferredWidth(r), flexibleWidth = LayoutUtility.GetFlexibleWidth(r),
                minHeight = LayoutUtility.GetMinHeight(r), preferredHeight = LayoutUtility.GetPreferredHeight(r),
                flexibleHeight = LayoutUtility.GetFlexibleHeight(r)
            };
        }
        [MenuItem("Tools/Layout Conformance/Export uGUI 2.0.0")]
        public static void Export() {
            var info = UnityEditor.PackageManager.PackageInfo.FindForAssembly(typeof(LayoutGroup).Assembly);
            if (Application.unityVersion != "6000.0.26f1" || info == null || info.version != "2.0.0")
                throw new InvalidOperationException("Requires pinned Unity 6000.0.26f1 and uGUI 2.0.0");
            string source = EditorUtility.OpenFilePanel("Layout cases", "", "json");
            if (source.Length == 0) return;
            string target = EditorUtility.SaveFilePanel("Unity measurements", "", "unity-results", "json");
            if (target.Length == 0) return;
            var suite = JsonUtility.FromJson<Document>(File.ReadAllText(source));
            if (suite == null || suite.Root == null || suite.Root.schemaVersion != 2 || suite.Root.cases == null)
                throw new InvalidDataException("Requires updated cases.json with schemaVersion=2 and explicit optional-block presence flags");
            var result = new ResultDocument();
            foreach (var c in suite.Root.cases) {
                var nodes = new RectTransform[c.nodes.Length];
                try {
                    for (int i = 0; i < nodes.Length; ++i) {
                        nodes[i] = new GameObject("LayoutComparisonFixture", typeof(RectTransform)).GetComponent<RectTransform>();
                        if (c.nodes[i].parent >= 0) nodes[i].SetParent(nodes[c.nodes[i].parent], false);
                        Apply(nodes[i], c.nodes[i], true);
                    }
                    var measured = new CaseResult { id = c.id };
                    for (int phase = 0; phase < 3; ++phase) {
                        if (phase == 1 && c.changes != null) {
                            foreach (var change in c.changes) {
                                if (change.hasTargetParent) {
                                    nodes[change.node].SetParent(nodes[change.targetParent], false);
                                    if (change.hasSiblingIndex) nodes[change.node].SetSiblingIndex(change.siblingIndex);
                                }
                                Apply(nodes[change.node], change, false);
                            }
                        }
                        for (int i = 0; i < (phase == 2 ? 100 : 1); ++i) Rebuild(nodes);
                        var state = new State();
                        foreach (var node in nodes) state.nodes.Add(Capture(node));
                        measured.states.Add(state);
                    }
                    result.Root.cases.Add(measured);
                }
                finally {
                    foreach (var node in nodes)
                        if (node != null) UnityEngine.Object.DestroyImmediate(node.gameObject);
                }
            }
            File.WriteAllText(target, JsonUtility.ToJson(result, true));
            Debug.Log("UnityLayoutExport: measured " + result.Root.cases.Count + " cases into " + target);
        }
    }
}
#endif
